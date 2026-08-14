# SmartRAG

[English README](README.en.md)

SmartRAG 是一个 Ruby 混合检索增强生成（RAG）库，结合向量检索、全文检索、LLM 总结问答与主题/标签管理，提供从文档导入到智能问答的全链路能力。

## 项目概览

SmartRAG 覆盖了 RAG 系统的完整生命周期：

- **文档处理**：支持本地文件与 URL 导入，自动格式转换（PDF/DOCX/HTML → Markdown）
- **智能切块**：基于 Markdown 标题切分 + 自适应大小切分 + 结构检测
- **向量嵌入**：通过 Ollama 生成文本向量，存储于 PostgreSQL pgvector
- **全文索引**：PostgreSQL tsvector 全文搜索，中文使用 pg_jieba 分词
- **混合检索**：向量语义检索 + 全文关键词检索 → RRF 融合 → 重排序
- **LLM 问答**：基于检索结果生成结构化回答（支持中/英/日/繁体中文）
- **主题与标签**：LLM 自动生成标签，支持主题组织和关联推荐
- **运维工具**：索引重建、去重、回填、搜索日志、系统统计

## 架构总览

```
┌─────────────────────────────────────────────┐
│            用户 API                           │
│   SmartRAG::SmartRAG  (lib/smart_rag.rb)     │
├─────────────────────────────────────────────┤
│           Retrieve 结构化检索                  │
│   SmartRAG::Retrieve  (retrieve.rb)          │
├──────────────┬──────────────┬────────────────┤
│  Core 层     │  Services 层  │  Chunking 层    │
│              │               │                │
│ Query        │ Hybrid        │ Markdown       │
│ Processor    │ Search Svc    │ Chunker        │
│              │               │                │
│ Document     │ Embedding     │ Smart          │
│ Processor    │ Service       │ Chunking       │
│              │               │                │
│ Embedding    │ Fulltext      │                │
│ (Core)       │ Search Svc    │                │
│              │               │                │
│ Fulltext     │ Tag           │                │
│ Manager      │ Service       │                │
│              │               │                │
│              │ Summarization │                │
│              │ Service       │                │
├──────────────┴──────────────┴────────────────┤
│               Models 层 (Sequel ORM)          │
│ SourceDocument / SourceSection / Embedding    │
│ Tag / ResearchTopic / SearchLog / SectionFts  │
├─────────────────────────────────────────────┤
│         Config 层 (YAML + ERB)                │
│   smart_rag.yml / database.yml / llm_config   │
├─────────────────────────────────────────────┤
│         Workers 层 (SmartPrompt)              │
│   get_embedding / analyze_content             │
└─────────────────────────────────────────────┘
```

## 默认模型配置

当前默认配置为本地 Ollama 兼容端点：

- Embedding 模型：`qwen3-embedding`（1024 维）
- 文本 LLM 模型：`qwen3`
- Embedding 端点：`http://localhost:11434/v1/embeddings`
- LLM 端点：`http://localhost:11434/v1/chat/completions`

可通过 `.env` 或 `config/smart_rag.yml` 覆盖以上默认值。

## 快速开始

### 1) 安装依赖

```bash
bundle install
```

### 2) 配置环境变量

```bash
cp .env.example .env
```

必填数据库变量：

- `SMARTRAG_DB_HOST`
- `SMARTRAG_DB_PORT`
- `SMARTRAG_DB_NAME`
- `SMARTRAG_DB_USER`
- `SMARTRAG_DB_PASSWORD`

### 3) 初始化数据库

```bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake db:seed
```

### 4) 导入测试文档（可选）

```bash
ruby test/import_doc.rb import
```

### 5) 运行示例程序

```bash
ruby examples/01_quick_start.rb
ruby examples/03_search_operations.rb
```

## API 参考

### 初始化

```ruby
require "smart_rag"

# 通过配置文件初始化
client = SmartRAG::SmartRAG.new("config/smart_rag.yml")

# 或通过 Hash 配置
client = SmartRAG::SmartRAG.new({
  database: {
    adapter: "postgresql",
    host: "localhost",
    database: "smart_rag_development",
    user: "rag_user",
    password: "your_password"
  }
})
```

### 知识库管理

| 方法 | 说明 | 返回值 |
|---|---|---|
| `add_document(path, options)` | 导入文档（本地文件或 URL） | `{ document_id:, section_count:, status: }` |
| `remove_document(id)` | 删除文档及关联段落/向量 | `{ success:, deleted_sections:, deleted_embeddings: }` |
| `get_document(id)` | 获取文档详情 | `{ id:, title:, description:, section_count:, metadata: }` |
| `list_documents(options)` | 分页列表，支持 title 搜索 | `{ documents:, total_count:, page:, per_page:, total_pages: }` |

```ruby
# 添加文档并自动生成向量
client.add_document("docs/report.md", generate_embeddings: true)

# 从 URL 导入
client.add_document("https://example.com/article.pdf")

# 分页查询
client.list_documents(page: 1, per_page: 10, search: "Python")
```

### 搜索（核心）

SmartRAG 提供三种搜索模式：**hybrid**（混合，默认）、**vector**（向量）、**fulltext**（全文）。

```ruby
# 统一搜索入口
results = client.search("机器学习是什么？",
  search_type: "hybrid",    # hybrid | vector | fulltext
  limit: 5,
  language: :zh_cn,          # :zh_cn | :en | :ja | 自动检测
  alpha: 0.7,                # 向量权重 (0.0-1.0)，仅 hybrid 有效
  include_content: true,
  include_metadata: true,
  generate_tags: false,      # 是否用 LLM 从查询中生成标签
  document_ids: [1, 2],      # 限定文档范围
  tags: ["AI", "机器学习"]    # 标签过滤/加权
)

# 单独使用各搜索模式
client.vector_search("神经网络架构", limit: 5)
client.fulltext_search('"deep reinforcement learning"', limit: 5)
client.hybrid_search("AI应用", language: :zh_cn)
```

#### 混合搜索流程

```
用户查询
    ↓
① 语言检测（中/日/英）
    ↓
② 可选：LLM 生成查询标签
    ↓
③ 生成查询向量
    ↓
④ 并行：向量搜索 + 全文搜索
    ↓
⑤ RRF 融合（Reciprocal Rank Fusion, k=60）
    ↓
⑥ 重排序（rerank_limit=64）
    ↓
⑦ 领域加权 + 类别多样性优化
    ↓
⑧ 返回结果
```

**RRF 融合权重**：向量 0.6 / 全文 0.4（可在 `config/fulltext_search.yml` 调整）。

#### 多语言支持

| 语言 | 全文搜索配置 | 分词方式 |
|---|---|---|
| 英文 | `pg_catalog.english` | stemming |
| 中文 | `jieba` | pg_jieba 分词 |
| 日文 | `pg_catalog.simple` | 基础分词 |
| 韩文 | `pg_catalog.simple` | 基础分词 |

### 结构化检索（SmartBrain 集成）

```ruby
plan = {
  queries: [
    { text: "machine learning basics", mode: "semantic", weight: 1.0 },
    { text: "deep neural networks", mode: "keyword", weight: 0.8 }
  ],
  budget: {
    candidate_k: 200,
    per_mode_k: { semantic: 30, keyword: 20 }
  },
  ranking: {
    rerank: { enabled: true }
  }
}

evidence_pack = client.retrieve(plan: plan)
# 返回 EvidencePack 格式：{ evidences:, stats:, explain:, warnings: }
```

### 标签管理

```ruby
# LLM 自动生成标签
result = client.generate_tags("这是一段关于深度学习和神经网络的文本...",
  max_tags: 10
)
# => { content_tags: ["深度学习", "神经网络"], category_tags: ["AI"] }

# 分页查询标签
client.list_tags(page: 1, per_page: 20, search: "AI")
```

### 主题管理

```ruby
# 创建主题
client.create_topic("AI 研究",
  description: "人工智能相关研究主题",
  tags: ["AI", "机器学习"],
  document_ids: [1, 3]
)

# 查询主题
client.get_topic(1)
client.list_topics(page: 1, per_page: 20, search: "AI")

# 更新主题
client.update_topic(1, title: "人工智能研究", tags: ["AI", "深度学习"])

# 删除主题
client.delete_topic(1)

# 文档与主题关联
client.add_document_to_topic(topic_id: 1, document_id: 5)
client.remove_document_from_topic(topic_id: 1, document_id: 5)

# 主题推荐（基于标签共现）
client.get_topic_recommendations(1, limit: 5)
```

### 系统运维

| 方法 | 说明 |
|---|---|
| `statistics` | 系统统计（文档/段落/主题/标签/向量数量） |
| `search_logs(limit:, search_type:)` | 查询搜索历史记录 |
| `rebuild_fts(document_id)` | 重建全文索引（不传参=全量） |
| `rebuild_embeddings(document_id)` | 重建向量嵌入（不传参=全量） |
| `reindex(document_id)` | 一键重建 FTS + 向量 |
| `dedupe_by_content_hash` | 按内容哈希去重重复文档 |
| `backfill_source_fields(dry_run:)` | 回填 source_uri/source_type/content_hash 字段 |
| `prepare_release_indexes(dry_run:)` | 发布前准备：backfill → dedupe → reindex |

```ruby
# 系统统计
stats = client.statistics
# => { document_count:, section_count:, topic_count:, tag_count:, embedding_count: }

# 搜索日志
client.search_logs(limit: 50, search_type: "hybrid")

# 预演发布准备（不写入）
client.prepare_release_indexes(dry_run: true)

# 执行发布准备
client.prepare_release_indexes
```

## 文档处理管线

```
URL / 文件路径
    ↓
① 下载（支持 301/302 重定向）
    ↓
② 提取元数据（大小、类型、时间）
    ↓
③ 格式转换（Markitdown: PDF/DOCX/HTML → Markdown）
    ↓
④ 创建 SourceDocument 记录
    ↓
⑤ 智能切块（Markdown 标题切分 → 超限大小切分）
    ↓
⑥ 存储 SourceSection 记录
    ↓
⑦ 可选：生成 Embedding + Tag
    ↓
⑧ 标记文档状态为 completed
```

支持的输入格式：`.md` / `.txt` / `.pdf` / `.docx` / `.html`

### 切块策略

- **MarkdownChunker**（默认）：按 H1-H3 标题切分，超限段落再按字符数拆分
- **SmartChunking**（高级）：结构检测 + 文档类型感知（法规/书籍/论文/手册），基于 token 合并

配置项（`config/smart_rag.yml`）：

```yaml
chunking:
  max_chars: 4000      # 最大块字符数
  overlap: 100         # 块间重叠字符数
  split_by_headers: true  # 优先按标题切分
  min_chunk_size: 100  # 最小块大小
```

## 数据模型

| 模型 | 表名 | 用途 |
|---|---|---|
| `SourceDocument` | `source_documents` | 文档元数据（标题、作者、来源类型、状态） |
| `SourceSection` | `source_sections` | 文档分段（标题、序号、内容、语言） |
| `Embedding` | `embeddings` | pgvector 向量存储 |
| `Tag` | `tags` | 标签（支持层级 parent_id） |
| `SectionTag` | `section_tags` | 段落到标签的多对多关联 |
| `ResearchTopic` | `research_topics` | 研究主题 |
| `ResearchTopicSection` | `research_topic_sections` | 主题到段落的关联 |
| `ResearchTopicTag` | `research_topic_tags` | 主题到标签的关联 |
| `SearchLog` | `search_logs` | 搜索记录（查询、耗时、结果数） |
| `SectionFts` | `section_fts` | 全文搜索物化视图 |

## 依赖

- **Ruby** >= 2.7
- **PostgreSQL** + `pgvector` 扩展 + `pg_jieba` 扩展
- **Sequel** ORM
- **SmartPrompt** gem（LLM 调用抽象层）
- **Nokogiri** / **Markitdown**（文档格式转换）

## 配置参考

主要配置文件：

| 文件 | 用途 |
|---|---|
| `config/smart_rag.yml` | 主配置（数据库、嵌入、搜索、切块、LLM、日志） |
| `config/database.yml` | 多环境数据库配置 |
| `config/llm_config.yml` | LLM 适配器配置（Ollama / SiliconFlow 等） |
| `config/fulltext_search.yml` | 全文搜索详细配置（语言、索引、性能） |

关键环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SMARTRAG_DB_NAME` | `smart_rag_development` | 数据库名 |
| `SMARTRAG_DB_USER` | `rag_user` | 数据库用户 |
| `SMARTRAG_DB_PASSWORD` | - | 数据库密码 |
| `EMBEDDING_MODEL` | `qwen3-embedding` | 嵌入模型 |
| `EMBEDDING_DIMENSIONS` | `1024` | 向量维度 |
| `LLM_MODEL` | `qwen3` | LLM 模型 |
| `DEFAULT_LANGUAGE` | `en` | 默认语言 |
| `ENABLE_JIEBA` | `true` | 启用中文分词 |

## 目录结构

```text
lib/
  smart_rag.rb                     # 主 API 入口（SmartRAG::SmartRAG 类）
  smart_rag/config.rb              # 配置加载（YAML + ERB）
  smart_rag/version.rb             # 版本号
  smart_rag/errors.rb              # 自定义异常类
  smart_rag/retrieve.rb            # 结构化检索（RetrievalPlan → EvidencePack）
  smart_rag/models.rb              # 模型加载和连接管理
  smart_rag/models/                # Sequel ORM 模型（11 张表）
  smart_rag/core/                  # 核心处理逻辑
    query_processor.rb             # 查询处理器（搜索 + 问答）
    document_processor.rb          # 文档处理器（导入 + 切块 + 存储）
    embedding.rb                   # 向量嵌入底层操作
    fulltext_manager.rb            # 全文索引管理
    markitdown_bridge.rb           # 文档格式转换桥接
  smart_rag/services/              # 服务层
    embedding_service.rb           # 嵌入服务（CRUD + 批量）
    vector_search_service.rb       # 向量检索服务
    fulltext_search_service.rb     # 全文检索服务
    hybrid_search_service.rb       # 混合检索服务（RRF + 重排序）
    summarization_service.rb       # LLM 总结问答服务
    tag_service.rb                 # 标签生成和管理服务
  smart_rag/chunker/               # 切块器
    markdown_chunker.rb            # Markdown 标题切分
  smart_rag/smart_chunking/        # 高级智能切块
    pipeline.rb / parser.rb        # 结构检测 + 类型感知切块
    merger.rb / tokenizer.rb       # Token 合并策略
  smart_rag/parsers/               # 解析器
    query_parser.rb                # 查询解析
config/                            # 运行时配置
db/                                # 数据库迁移和种子 SQL
examples/                          # 示例代码（6 个场景）
test/                              # E2E 测试脚本 + 测试文档
spec/                              # RSpec 测试
workers/                           # SmartPrompt worker 定义
```

## 开发常用命令

```bash
# 运行测试
bundle exec rspec                      # RSpec 单元/集成测试
SMARTRAG_LIVE_SPECS=1 bundle exec rspec spec/documentation # 真实模型文档示例
ruby test/test_rag.rb                  # E2E 测试脚本

# 数据库操作
bundle exec rake db:create             # 创建数据库
bundle exec rake db:migrate            # 运行迁移
bundle exec rake db:seed               # 导入种子数据
bundle exec rake db:reset              # 重建数据库

# 运维操作
bundle exec rake db:backfill_source_fields  # 回填字段
bundle exec rake db:prepare_release         # 发布前准备

# 构建
gem build smart_rag.gemspec            # 构建 gem 包

# 导入测试文档
ruby test/import_doc.rb import

# 重建嵌入
ruby test/reembed_all.rb
```

## 文档导航

完整文档清单、阅读顺序和维护建议见 `docs/DOCUMENTATION_INDEX.md`。  
英文版见 `docs/DOCUMENTATION_INDEX.en.md`。

其他重要文档：

- `docs/design.md` — 系统设计文档
- `docs/API_DOCUMENTATION.md` — API 详细文档
- `docs/SETUP_GUIDE.md` — 环境搭建指南
- `docs/USAGE_EXAMPLES.md` — 使用示例
- `docs/Hybrid_Reranking.md` — 混合检索与重排序说明
- `docs/SmartChunking.md` — 智能切块说明
- `docs/MIGRATION_GUIDE.md` — 迁移指南
- `docs/PERFORMANCE_GUIDE.md` — 性能优化指南
- `ER-diagram.mmd` — ER 图

## 说明

- 部分历史文档仍保留旧默认值（如 OpenAI 示例）。运行时配置以 `config/smart_rag.yml` 为准。

## 许可证

MIT
# Media HTTP API

SmartRAG exposes a small Rack-compatible app for retrieval and media ingestion:

```ruby
require 'smart_rag'
require 'smart_rag/http_app'

rag = SmartRAG::SmartRAG.new(config)
app = SmartRAG::HttpApp.new(
  rag: rag,
  extractors: {
    audio_transcriber: audio_transcriber,
    video_transcriber: video_transcriber,
    image_describer: image_describer,
    frame_describer: frame_describer,
    ocr_extractor: ocr_extractor
  }
)
```

Endpoints:

- `POST /v1/retrieve`: JSON `{ "plan": { ... } }`
- `POST /v1/media`: JSON URL import or multipart fields `operation`, `options`, `file`
- `POST /v1/media` with `options.async=true`: queue the import and return HTTP 202
- `GET /v1/media/jobs?status=failed&limit=20&offset=0`: list and filter jobs
- `GET /v1/media/jobs/:id`: inspect queued, processing, completed, partial, or failed state
- `POST /v1/media/jobs/:id/cancel`: cancel a queued job
- `POST /v1/media/jobs/:id/retry`: manually retry a failed job
- `GET /v1/media/jobs/stats`: queue counts, oldest queued age, and stale processing count
- `GET /healthz`

Start the bundled Rack entrypoint with a Rack server such as Puma:

```bash
SMARTRAG_CONFIG_PATH=config/smart_rag.yml bundle exec puma -p 9393 config.ru
```

Allowed operations are `add_document`, `add_media`, `add_image`, `add_audio`, and `add_video`. Extractor objects are server-side configuration and are never accepted from HTTP payloads.

Run migration `013_create_media_jobs`, then start a worker with:

```bash
bundle exec smart-rag-media-worker
# For cron or one-shot processing:
bundle exec smart-rag-media-worker --once --batch-size 20
```

The `media` section in `config/smart_rag.yml` configures file/duration limits, URL allowlists, command timeouts, the optional local content-addressed store, OpenAI-compatible vision/transcription, Tesseract OCR, and job retry count. Asynchronous multipart uploads are copied to `SMARTRAG_MEDIA_JOB_UPLOAD_DIR`. Completed/canceled uploads are removed immediately; failed uploads remain available for manual retry until terminal jobs are pruned.

On startup the worker requeues `processing` jobs older than `MEDIA_JOB_STALE_AFTER_SECONDS`. Once per hour it removes terminal jobs older than `MEDIA_JOB_RETENTION_SECONDS` (defaults: 15 minutes and 7 days). `/healthz` includes the same queue statistics as the stats endpoint, making backlog and expired worker leases observable without inspecting PostgreSQL directly.

## Media P3 production controls

Migration `015_add_media_leases_and_objects` adds worker heartbeat leases, per-principal idempotency, S3/MinIO storage, reference-counted object cleanup, and optional HTTP authentication/quotas.

Migration `016_add_document_principals_and_staging_references` is the data-integrity follow-up. It protects retained failed-job staging objects with an explicit foreign key, makes failed synchronous imports discoverable by object GC, and adds principal ownership to documents. Authenticated retrieval, document reads/lists/deletion, and statistics are owner-scoped; direct embedded calls remain global unless a `principal:` is supplied.

Run all migrations through `017_add_media_job_request_fingerprint` before deploying the current queue code. Migration 017 backfills a canonical SHA-256 request fingerprint for existing jobs and makes the new column required.

Send `Idempotency-Key` with an asynchronous import to make retries safe. Keys are isolated by authenticated principal. Reusing a key with the same operation, source, and canonicalized options returns the original job with `deduplicated: true`; reusing it with a different payload returns HTTP `409` with `code: "idempotency_conflict"`. Nested hash key order and symbol/string keys do not change the fingerprint, while array order remains significant. Workers update `heartbeat_at` while extraction is running, so long videos are not requeued merely because their original `started_at` is old.

For S3 or MinIO:

```bash
MEDIA_CONTENT_STORE_ENABLED=true
MEDIA_CONTENT_STORE_PROVIDER=s3
MEDIA_S3_BUCKET=smart-rag-media
MEDIA_S3_REGION=us-east-1
MEDIA_S3_ENDPOINT=http://minio:9000       # omit for AWS S3
MEDIA_S3_FORCE_PATH_STYLE=true            # usually required by MinIO
MEDIA_S3_ACCESS_KEY_ID=...
MEDIA_S3_SECRET_ACCESS_KEY=...
```

`aws-sdk-s3` is a runtime dependency and is loaded only when the S3 provider is selected. Stored objects are tracked in `media_objects` and `media_object_references`; deleting a document releases its reference, and the worker removes zero-reference objects during hourly garbage collection. Retained jobs, including failed jobs, protect their staging objects from garbage collection until the job is pruned.

Enable Bearer authentication and PostgreSQL-backed quotas with:

```bash
SMARTRAG_HTTP_AUTH_ENABLED=true
SMARTRAG_HTTP_PRINCIPAL=production-agent
SMARTRAG_HTTP_TOKEN=replace-with-a-secret
SMARTRAG_REQUESTS_PER_MINUTE=120
SMARTRAG_UPLOAD_BYTES_PER_DAY=10737418240
```

All endpoints except `/healthz` then require `Authorization: Bearer ...`. Job reads and mutations are scoped to the authenticated principal. Retrieval also injects the authenticated principal, limits backend search to owned document IDs, and rechecks every returned candidate against PostgreSQL, so a backend that ignores `document_ids` cannot leak another principal's evidence. The current YAML/env entrypoint supports one token; embedded applications can pass a `tokens: { principal => token }` map to `HttpAccessPolicy` for multiple callers.

### Real storage and isolation verification

The MinIO integration spec is opt-in because it performs real object writes and deletes. Start MinIO, create or allow creation of the configured bucket, load the PostgreSQL test environment, and run:

```bash
SMARTRAG_MINIO_E2E=1 \
SMARTRAG_MINIO_ENDPOINT=http://127.0.0.1:19000 \
SMARTRAG_MINIO_BUCKET=smart-rag-e2e \
SMARTRAG_MINIO_ACCESS_KEY=smart-rag-e2e \
SMARTRAG_MINIO_SECRET_KEY=smart-rag-e2e-secret \
bundle exec rspec spec/integration/minio_content_store_spec.rb
```

This verifies cross-instance upload/materialization, asynchronous worker consumption of an `s3://` staging URI, reference attachment/detachment, real object deletion, and failed-job GC protection. PostgreSQL-backed tenant and idempotency coverage can be run independently with:

```bash
bundle exec rspec \
  spec/integration/media_tenant_isolation_spec.rb \
  spec/integration/media_p3_spec.rb
```

Those specs cover Bearer-token HTTP retrieval isolation, invalid-token `401`, same-payload deduplication, different-payload `409`, and concurrent inserts racing on the same principal/key.
