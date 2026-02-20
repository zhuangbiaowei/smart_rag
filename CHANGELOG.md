# Changelog

## Unreleased

### Added
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
- `retrieve` 现支持 `global_filters.source_type` 与 `global_filters.source_uri_prefix` 的执行过滤。
- `retrieve` 新增 `global_filters.topic_ids` 的执行过滤（按 section-topic 关系过滤）。
- `retrieve` 新增 `budget.diversity.by_source` 执行约束。
- `dedupe_by_content_hash` 从“仅 content_hash”升级为“`source_uri + content_hash`”去重。
- 检索日志 (`search_logs.filters`) 新增保存 `plan/stats/explain/warnings`，用于回放与调试。

### Compatibility
- 保留 `search(...)` 旧接口，不破坏现有调用。
- 对未支持字段通过 `explain.ignored_fields` 明确返回，不做静默忽略。
