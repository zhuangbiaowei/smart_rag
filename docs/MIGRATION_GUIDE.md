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
