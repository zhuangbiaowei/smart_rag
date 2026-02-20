# SmartRAG

[English README](README.en.md)

SmartRAG 是一个 Ruby 混合检索增强生成（RAG）库，结合向量检索、全文检索与主题/标签管理，用于文档智能检索与问答场景。

## 项目概览

- 混合检索：向量检索 + 全文检索 + 权重融合
- 支持本地文件与 URL 文档导入
- 提供主题与标签管理 API
- 提供搜索日志与系统统计能力
- 内置示例脚本便于快速上手

## 默认模型配置

当前默认配置为本地 Ollama 兼容端点：

- Embedding 模型：`qwen3-embedding`
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

## 最小调用示例

```ruby
require "smart_rag"

config = SmartRAG::Config.load("config/smart_rag.yml")
client = SmartRAG::SmartRAG.new(config)

client.add_document("test/python_basics.md", generate_embeddings: true)
results = client.search("机器学习是什么？", search_type: "hybrid", limit: 5)

puts results[:results].map { |r| r[:section_title] }
```

## 开发常用命令

- `bundle exec rspec`：运行 RSpec 测试
- `ruby test/test_rag.rb`：运行端到端测试脚本
- `bundle exec rake db:reset`：重建数据库
- `gem build smart_rag.gemspec`：构建 gem 包

## 运维命令（发布前）

标准发布前步骤（推荐）：

1. 迁移数据库

```bash
bundle exec rake db:migrate
```

2. 回填历史数据字段（`source_type/source_uri/content_hash`）

```bash
bundle exec rake db:backfill_source_fields
```

3. 执行一键检索发布准备（backfill -> dedupe -> reindex）

```bash
bundle exec rake db:prepare_release
```

仅预演（不写入）：

```bash
DRY_RUN=1 bundle exec rake db:backfill_source_fields
DRY_RUN=1 bundle exec rake db:prepare_release
```

## 目录结构

```text
lib/
  smart_rag.rb                 # 主 API 入口
  smart_rag/core/              # 核心处理逻辑
  smart_rag/services/          # 搜索/标签/嵌入服务
config/                        # 运行时配置
db/                            # 迁移与种子 SQL
examples/                      # 示例代码
test/                          # 手工/E2E 脚本与样例文档
spec/                          # RSpec 测试
```

## 文档导航

完整文档清单、阅读顺序和维护建议见 `docs/DOCUMENTATION_INDEX.md`。  
英文版见 `docs/DOCUMENTATION_INDEX.en.md`。

## 说明

- 部分历史文档仍保留旧默认值（如 OpenAI 示例）。运行时配置以 `config/smart_rag.yml` 为准。

## 许可证

MIT
