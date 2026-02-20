# Migration Guide

## Version Matrix

| SmartRAG Version | Notes |
| --- | --- |
| 1.0.x | Initial stable APIs |
| 1.1.x | Return-shape updates |
| 1.2.x | Search option rename |
| 1.3.x | Runtime/platform updates |

## Breaking Changes

### 1.1.x

- search() method now returns a Hash
- add_document() return value structure changed

### 1.2.x

- alpha parameter renamed to vector_weight

### 1.3.x

- Minimum Ruby version increased to 3.3.0
- PostgreSQL 16+ required

## SQL Migration Examples

```sql
ALTER TABLE search_logs ADD COLUMN IF NOT EXISTS metadata jsonb;
```

```sql
CREATE INDEX IF NOT EXISTS idx_search_logs_created_at
ON search_logs (created_at);
```

## Coverage

- Migration steps for Document Management
- Migration steps for Search Operations
- Migration steps for Research Topics
- Migration steps for Tag Management
- Migration steps for Hybrid Search
- Migration steps for Vector Search
- Migration steps for Full-Text Search
- Migration steps for Error Handling
- Migration steps for Performance Optimization

## Retrieval Refactor Migration (2026-02)

### Scope

- `retrieve(plan) -> EvidencePack` contract rollout
- `source_documents` new columns: `source_type/source_uri/content_hash`
- index governance pipeline: backfill, dedupe, reindex

### Recommended Steps

1. Backup database.
2. Run migrations:

```bash
bundle exec rake db:migrate
```

3. Backfill historical documents:

```bash
bundle exec rake db:backfill_source_fields
```

Optional dry run:

```bash
DRY_RUN=1 bundle exec rake db:backfill_source_fields
```

4. Run release preparation pipeline:

```bash
bundle exec rake db:prepare_release
```

Optional dry run:

```bash
DRY_RUN=1 bundle exec rake db:prepare_release
```

5. Verify:
- `source_documents.source_type/source_uri/content_hash` populated
- `retrieve(plan)` returns `explain.filters_applied`
- `search_logs.filters` contains `plan/stats/explain`

### Rollback Notes

- Schema rollback:

```bash
bundle exec rake db:rollback[1]
```

- If backfill/dedupe/reindex already ran, restore from database backup for full rollback.
