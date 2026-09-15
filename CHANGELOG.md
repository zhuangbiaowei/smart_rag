# Changelog

## 0.2.2 - 2026-09-15

### Fixed
- 修正 gemspec 中 homepage/source_code_uri/changelog_uri 指向错误仓库地址的问题。

## 0.2.1 - 2026-09-15

### Changed
- 升级 `smart_prompt` 依赖至 `~> 0.5.4`。

## 0.2.0 - 2026-08-14

### Added
- 新增图片、音频、视频和通用媒体导入 API，以及可降级为 `partial` 的媒体元数据与语义提取。
- 新增 Rack HTTP 服务、Bearer 认证、principal 隔离和 PostgreSQL 配额控制。
- 新增 PostgreSQL 持久化媒体任务队列、取消/重试、heartbeat lease、卡死任务恢复和保留期清理。
- 新增本地与 S3/MinIO 内容寻址存储、对象引用计数和垃圾回收。
- 新增按 principal 隔离的幂等键与规范化请求指纹；冲突请求返回 `idempotency_conflict`。
- 新增数据库迁移 012-017，覆盖 section metadata、媒体任务、租约、对象引用、文档所有权和请求指纹。
- 新增 `smart-rag-media-worker` 可执行文件和 Rack `config.ru` 启动入口。
- 新增 `retrieve(plan:)` 结构化检索入口（`RetrievalPlan -> EvidencePack`）。
- 新增 `SmartRAG::Retrieve` 执行器：支持多 query、mode 映射、signals、provenance、stats、explain。
- 新增索引治理接口：
  - `rebuild_fts(document_id=nil)`
  - `rebuild_embeddings(document_id=nil)`
  - `reindex(document_id=nil)`
  - `dedupe_by_content_hash`
- 新增 `source_documents` 字段与索引：
  - `source_type`
  - `source_uri`
  - `content_hash`
- 新增轻量单测入口 `spec/unit_spec_helper.rb`（不依赖数据库连接）。
- 新增回填任务：`rake db:backfill_source_fields`（历史数据回填新字段）。
- 新增一键发布任务：`rake db:prepare_release`（backfill -> dedupe -> reindex）。
- 新增 API：
  - `backfill_source_fields(limit: nil, dry_run: false)`
  - `prepare_release_indexes(document_id: nil, dry_run: false)`

### Changed
- 文档、检索、统计和媒体任务 API 支持 principal 所有权过滤。
- 文档与 section metadata 在全文、混合和结构化检索结果中统一合并。
- URL 下载新增私网地址限制、主机白名单、重定向上限、超时和流式大小限制。
- `retrieve` 现支持 `global_filters.source_type` 与 `global_filters.source_uri_prefix` 的执行过滤。
- `retrieve` 新增 `global_filters.topic_ids` 的执行过滤（按 section-topic 关系过滤）。
- `retrieve` 新增 `budget.diversity.by_source` 执行约束。
- `dedupe_by_content_hash` 从“仅 content_hash”升级为“`source_uri + content_hash`”去重。
- 检索日志 (`search_logs.filters`) 新增保存 `plan/stats/explain/warnings`，用于回放与调试。

### Compatibility
- 保留 `search(...)` 旧接口，不破坏现有调用。
- 对未支持字段通过 `explain.ignored_fields` 明确返回，不做静默忽略。
