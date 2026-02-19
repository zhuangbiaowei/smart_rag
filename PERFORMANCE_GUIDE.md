# Performance Guide

## Performance Optimization

Target latency:
- P50 < 150ms
- P95 < 250ms
- P99 < 500ms

## PostgreSQL Tuning

Recommended baseline:

```conf
shared_buffers = 2GB
work_mem = 64MB
maintenance_work_mem = 512MB
max_connections = 200
```

Notes:
- `shared_buffers` can be tuned around 25% of total RAM.
- OS page cache and related settings can use the remaining 75% of total RAM.

## Indexing Strategies

Vector index (IVFFLAT):

```sql
CREATE INDEX CONCURRENTLY idx_embeddings_ivfflat
ON embeddings USING ivfflat (vector vector_cosine_ops)
WITH (lists = 100);
```

Vector index (HNSW):

```sql
CREATE INDEX CONCURRENTLY idx_embeddings_hnsw
ON embeddings USING hnsw (vector vector_cosine_ops);
```

Full-text index:

```sql
CREATE INDEX CONCURRENTLY idx_section_fts_content
ON section_fts USING gin (fts_combined);
```

## Related Features

- Document Management
- Search Operations
- Research Topics
- Tag Management
- Hybrid Search
- Vector Search
- Full-Text Search
- Error Handling
