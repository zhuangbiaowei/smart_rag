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

## Media Queue Integrity Migration (015-017, 2026-08)

### Scope

- `015_add_media_leases_and_objects`: heartbeat leases, per-principal idempotency keys, object references, and API quota counters.
- `016_add_document_principals_and_staging_references`: document ownership and an explicit foreign key from retained jobs to staging media objects.
- `017_add_media_job_request_fingerprint`: canonical request fingerprints used to distinguish a retry from conflicting reuse of an idempotency key.

### Deployment Order

1. Stop media workers and pause asynchronous ingestion. Existing synchronous retrieval may remain online.
2. Back up PostgreSQL.
3. Run migrations through 017 before deploying the current queue code:

```bash
bundle exec rake db:migrate
```

4. Verify the schema version and required column:

```sql
SELECT * FROM schema_info;

SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'media_jobs'
  AND column_name = 'request_fingerprint';
```

The expected migration version is `17`, and `request_fingerprint.is_nullable` must be `NO`. Migration 017 backfills existing jobs before adding the `NOT NULL` constraint.

5. Deploy the application and worker together, then resume asynchronous ingestion.
6. Verify that an identical principal/key/payload returns the original job, while the same principal/key with a different source or options returns HTTP 409 with `code: "idempotency_conflict"`.

### Operational Notes

- The fingerprint includes operation, logical source, and recursively canonicalized serializable options. Hash key order and symbol/string keys are normalized; array order is preserved.
- Different principals may reuse the same idempotency key.
- Tools that insert directly into `media_jobs` must now supply `request_fingerprint`; normal application code must use `MediaJobQueue#enqueue`.
- Retained jobs, including failed jobs, protect `staging_media_object_id` from object garbage collection. Pruning the job releases that protection.

### Rollback Notes

Rollback across migration 017 requires stopping application and worker processes first. Older code does not write `request_fingerprint`, while current code expects it to exist. Rolling back 016 can also remove staging-object protection and document ownership, so restore the matching application version at the same time. Prefer a forward fix after production jobs have been created under the new schema.
