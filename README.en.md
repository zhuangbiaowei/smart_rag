# SmartRAG

[中文 README](README.md)

SmartRAG is a Ruby-based hybrid Retrieval-Augmented Generation (RAG) library that combines vector retrieval, full-text search, LLM-powered Q&A summarization, and topic/tag management — covering the full pipeline from document ingestion to intelligent question answering.

## Overview

SmartRAG covers the complete RAG lifecycle:

- **Document Processing**: local files and URL import with automatic format conversion (PDF/DOCX/HTML → Markdown)
- **Smart Chunking**: Markdown heading-based splitting + adaptive size splitting + structure detection
- **Vector Embedding**: text embeddings via Ollama, stored in PostgreSQL pgvector
- **Full-Text Indexing**: PostgreSQL tsvector search, Chinese segmented with pg_jieba
- **Hybrid Retrieval**: vector semantic search + full-text keyword search → RRF fusion → reranking
- **LLM Q&A**: structured answers from search results (supports EN/ZH/JA/Traditional Chinese)
- **Topics & Tags**: LLM-generated tags, topic organization and association recommendations
- **Operations Tooling**: index rebuild, deduplication, backfill, search logs, system statistics

## Architecture

```
┌─────────────────────────────────────────────┐
│            Public API                        │
│   SmartRAG::SmartRAG  (lib/smart_rag.rb)     │
├─────────────────────────────────────────────┤
│        Retrieve Structured Retrieval         │
│   SmartRAG::Retrieve  (retrieve.rb)          │
├──────────────┬──────────────┬────────────────┤
│  Core Layer  │ Services Layer│ Chunking Layer │
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
│              Models Layer (Sequel ORM)        │
│ SourceDocument / SourceSection / Embedding    │
│ Tag / ResearchTopic / SearchLog / SectionFts  │
├─────────────────────────────────────────────┤
│         Config Layer (YAML + ERB)             │
│   smart_rag.yml / database.yml / llm_config   │
├─────────────────────────────────────────────┤
│         Workers Layer (SmartPrompt)           │
│   get_embedding / analyze_content             │
└─────────────────────────────────────────────┘
```

## Default Model Setup

Current defaults use local Ollama-compatible endpoints:

- Embedding model: `qwen3-embedding` (1024 dimensions)
- Text LLM model: `qwen3`
- Embedding endpoint: `http://localhost:11434/v1/embeddings`
- LLM endpoint: `http://localhost:11434/v1/chat/completions`

You can override these via `.env` or `config/smart_rag.yml`.

## Quick Start

### 1) Install dependencies

```bash
bundle install
```

### 2) Configure environment

```bash
cp .env.example .env
```

Required DB variables:

- `SMARTRAG_DB_HOST`
- `SMARTRAG_DB_PORT`
- `SMARTRAG_DB_NAME`
- `SMARTRAG_DB_USER`
- `SMARTRAG_DB_PASSWORD`

### 3) Setup database

```bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake db:seed
```

### 4) Import test docs (optional)

```bash
ruby test/import_doc.rb import
```

### 5) Run sample scripts

```bash
ruby examples/01_quick_start.rb
ruby examples/03_search_operations.rb
```

## API Reference

### Initialization

```ruby
require "smart_rag"

# From a config file
client = SmartRAG::SmartRAG.new("config/smart_rag.yml")

# Or from a Hash
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

### Knowledge Base Management

| Method | Description | Returns |
|---|---|---|
| `add_document(path, options)` | Import a document (local file or URL) | `{ document_id:, section_count:, status: }` |
| `remove_document(id)` | Delete a document with all sections/embeddings | `{ success:, deleted_sections:, deleted_embeddings: }` |
| `get_document(id)` | Get document details | `{ id:, title:, description:, section_count:, metadata: }` |
| `list_documents(options)` | Paginated listing with title search | `{ documents:, total_count:, page:, per_page:, total_pages: }` |

```ruby
# Import and auto-generate embeddings
client.add_document("docs/report.md", generate_embeddings: true)

# Import from URL
client.add_document("https://example.com/article.pdf")

# Paginated listing
client.list_documents(page: 1, per_page: 10, search: "Python")
```

### Search (Core)

SmartRAG provides three search modes: **hybrid** (default), **vector**, and **fulltext**.

```ruby
# Unified search entry point
results = client.search("What is machine learning?",
  search_type: "hybrid",    # hybrid | vector | fulltext
  limit: 5,
  language: :en,             # :en | :zh_cn | :ja | auto-detect
  alpha: 0.7,                # vector weight (0.0-1.0), hybrid only
  include_content: true,
  include_metadata: true,
  generate_tags: false,      # use LLM to generate tags from query
  document_ids: [1, 2],      # restrict to specific documents
  tags: ["AI", "ML"]         # tag filtering/boosting
)

# Individual search modes
client.vector_search("neural network architectures", limit: 5)
client.fulltext_search('"deep reinforcement learning"', limit: 5)
client.hybrid_search("AI applications", language: :en)
```

#### Hybrid Search Pipeline

```
User Query
    ↓
① Language Detection (EN/ZH/JA)
    ↓
② Optional: LLM query tag generation
    ↓
③ Query vector embedding
    ↓
④ Parallel: vector search + full-text search
    ↓
⑤ RRF Fusion (Reciprocal Rank Fusion, k=60)
    ↓
⑥ Reranking (rerank_limit=64)
    ↓
⑦ Domain boosting + category diversity
    ↓
⑧ Return results
```

**RRF weights**: vector 0.6 / fulltext 0.4 (adjustable in `config/fulltext_search.yml`).

#### Multilingual Support

| Language | FTS Configuration | Tokenizer |
|---|---|---|
| English | `pg_catalog.english` | stemming |
| Chinese | `jieba` | pg_jieba segmentation |
| Japanese | `pg_catalog.simple` | basic |
| Korean | `pg_catalog.simple` | basic |

### Structured Retrieval (SmartBrain Integration)

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
# Returns EvidencePack: { evidences:, stats:, explain:, warnings: }
```

### Tag Management

```ruby
# LLM auto-generate tags
result = client.generate_tags("This is a text about deep learning and neural networks...",
  max_tags: 10
)
# => { content_tags: ["deep learning", "neural networks"], category_tags: ["AI"] }

# Paginated tag listing
client.list_tags(page: 1, per_page: 20, search: "AI")
```

### Topic Management

```ruby
# Create topic
client.create_topic("AI Research",
  description: "Artificial intelligence research topics",
  tags: ["AI", "Machine Learning"],
  document_ids: [1, 3]
)

# Query topics
client.get_topic(1)
client.list_topics(page: 1, per_page: 20, search: "AI")

# Update topic
client.update_topic(1, title: "Artificial Intelligence Research", tags: ["AI", "DL"])

# Delete topic
client.delete_topic(1)

# Document-topic association
client.add_document_to_topic(topic_id: 1, document_id: 5)
client.remove_document_from_topic(topic_id: 1, document_id: 5)

# Topic recommendations (based on tag co-occurrence)
client.get_topic_recommendations(1, limit: 5)
```

### System Operations

| Method | Description |
|---|---|
| `statistics` | System stats (documents/sections/topics/tags/embeddings count) |
| `search_logs(limit:, search_type:)` | Query search history |
| `rebuild_fts(document_id)` | Rebuild full-text indexes (omit for all) |
| `rebuild_embeddings(document_id)` | Rebuild vector embeddings (omit for all) |
| `reindex(document_id)` | Rebuild both FTS + embeddings |
| `dedupe_by_content_hash` | Deduplicate documents by content hash |
| `backfill_source_fields(dry_run:)` | Backfill source_uri/source_type/content_hash fields |
| `prepare_release_indexes(dry_run:)` | Pre-release pipeline: backfill → dedupe → reindex |

```ruby
# System statistics
stats = client.statistics
# => { document_count:, section_count:, topic_count:, tag_count:, embedding_count: }

# Search logs
client.search_logs(limit: 50, search_type: "hybrid")

# Dry run release prep
client.prepare_release_indexes(dry_run: true)

# Execute release prep
client.prepare_release_indexes
```

## Document Processing Pipeline

```
URL / file path
    ↓
① Download (with 301/302 redirect support)
    ↓
② Extract metadata (size, type, timestamp)
    ↓
③ Format conversion (Markitdown: PDF/DOCX/HTML → Markdown)
    ↓
④ Create SourceDocument record
    ↓
⑤ Smart chunking (heading-based → size-based fallback)
    ↓
⑥ Store SourceSection records
    ↓
⑦ Optional: generate Embedding + Tag
    ↓
⑧ Mark document status as completed
```

Supported input formats: `.md` / `.txt` / `.pdf` / `.docx` / `.html`

### Chunking Strategies

- **MarkdownChunker** (default): split by H1-H3 headings, oversized chunks split further by character count
- **SmartChunking** (advanced): structure detection + document type awareness (laws/books/papers/manuals), token-based merging

Configuration (`config/smart_rag.yml`):

```yaml
chunking:
  max_chars: 4000        # max characters per chunk
  overlap: 100           # character overlap between chunks
  split_by_headers: true # split by markdown headers first
  min_chunk_size: 100    # discard chunks smaller than this
```

## Data Model

| Model | Table | Purpose |
|---|---|---|
| `SourceDocument` | `source_documents` | Document metadata (title, author, source type, state) |
| `SourceSection` | `source_sections` | Document sections (title, number, content, language) |
| `Embedding` | `embeddings` | pgvector vector storage |
| `Tag` | `tags` | Tags (supports hierarchy via parent_id) |
| `SectionTag` | `section_tags` | Many-to-many: section ↔ tag |
| `ResearchTopic` | `research_topics` | Research topics |
| `ResearchTopicSection` | `research_topic_sections` | Topic ↔ section association |
| `ResearchTopicTag` | `research_topic_tags` | Topic ↔ tag association |
| `SearchLog` | `search_logs` | Search records (query, duration, result count) |
| `SectionFts` | `section_fts` | Full-text search materialized view |

## Dependencies

- **Ruby** >= 2.7
- **PostgreSQL** + `pgvector` extension + `pg_jieba` extension
- **Sequel** ORM
- **SmartPrompt** gem (LLM abstraction layer)
- **Nokogiri** / **Markitdown** (document format conversion)

## Configuration Reference

Main configuration files:

| File | Purpose |
|---|---|
| `config/smart_rag.yml` | Main config (database, embedding, search, chunking, LLM, logging) |
| `config/database.yml` | Multi-environment database config |
| `config/llm_config.yml` | LLM adapter config (Ollama / SiliconFlow etc.) |
| `config/fulltext_search.yml` | Full-text search details (languages, indexes, performance) |

Key environment variables:

| Variable | Default | Description |
|---|---|---|
| `SMARTRAG_DB_NAME` | `smart_rag_development` | Database name |
| `SMARTRAG_DB_USER` | `rag_user` | Database user |
| `SMARTRAG_DB_PASSWORD` | - | Database password |
| `EMBEDDING_MODEL` | `qwen3-embedding` | Embedding model |
| `EMBEDDING_DIMENSIONS` | `1024` | Vector dimensions |
| `LLM_MODEL` | `qwen3` | LLM model |
| `DEFAULT_LANGUAGE` | `en` | Default language |
| `ENABLE_JIEBA` | `true` | Enable Chinese segmentation |

## Project Structure

```text
lib/
  smart_rag.rb                     # Main API entry (SmartRAG::SmartRAG class)
  smart_rag/config.rb              # Config loading (YAML + ERB)
  smart_rag/version.rb             # Version
  smart_rag/errors.rb              # Custom error classes
  smart_rag/retrieve.rb            # Structured retrieval (RetrievalPlan → EvidencePack)
  smart_rag/models.rb              # Model loading and connection management
  smart_rag/models/                # Sequel ORM models (10 tables)
  smart_rag/core/                  # Core processing logic
    query_processor.rb             # Query processor (search + Q&A)
    document_processor.rb          # Document processor (import + chunk + store)
    embedding.rb                   # Low-level embedding operations
    fulltext_manager.rb            # Full-text index management
    markitdown_bridge.rb           # Document format conversion bridge
  smart_rag/services/              # Service layer
    embedding_service.rb           # Embedding service (CRUD + batch)
    vector_search_service.rb       # Vector search service
    fulltext_search_service.rb     # Full-text search service
    hybrid_search_service.rb       # Hybrid search service (RRF + reranking)
    summarization_service.rb       # LLM Q&A summarization service
    tag_service.rb                 # Tag generation and management service
  smart_rag/chunker/               # Chunkers
    markdown_chunker.rb            # Markdown heading-based chunker
  smart_rag/smart_chunking/        # Advanced smart chunking
    pipeline.rb / parser.rb        # Structure detection + type-aware chunking
    merger.rb / tokenizer.rb       # Token merging strategies
  smart_rag/parsers/               # Parsers
    query_parser.rb                # Query parser
config/                            # Runtime configuration
db/                                # Database migrations and seed SQL
examples/                          # Example scripts (6 scenarios)
test/                              # E2E test scripts + sample documents
spec/                              # RSpec tests
workers/                           # SmartPrompt worker definitions
```

## Development Commands

```bash
# Run tests
bundle exec rspec                      # RSpec unit/integration tests
SMARTRAG_LIVE_SPECS=1 bundle exec rspec spec/documentation # Live-model documentation examples
ruby test/test_rag.rb                  # E2E test script

# Database operations
bundle exec rake db:create             # Create database
bundle exec rake db:migrate            # Run migrations
bundle exec rake db:seed               # Seed data
bundle exec rake db:reset              # Recreate database

# Operations
bundle exec rake db:backfill_source_fields  # Backfill fields
bundle exec rake db:prepare_release         # Pre-release pipeline

# Build
gem build smart_rag.gemspec            # Build gem package

# Import test documents
ruby test/import_doc.rb import

# Rebuild embeddings
ruby test/reembed_all.rb
```

## Media Storage, Tenant Isolation, and Idempotency

Run database migrations through `017_add_media_job_request_fingerprint` before deploying the current asynchronous media queue. Migrations 015 and 016 add leases, object references, authenticated document ownership, and explicit staging-object protection. Migration 017 backfills and requires a canonical SHA-256 fingerprint for every queued request.

For asynchronous `POST /v1/media` requests, send `Idempotency-Key`. Repeating the same operation, source, and canonicalized options for the same authenticated principal returns the original job with `deduplicated: true`. Reusing the key with a different payload returns HTTP `409` and `code: "idempotency_conflict"`. Different principals may use the same key independently.

Configure AWS S3 or MinIO with the `MEDIA_CONTENT_STORE_*` and `MEDIA_S3_*` variables documented in `.env.example`. MinIO normally requires `MEDIA_S3_FORCE_PATH_STYLE=true`. The `aws-sdk-s3` runtime dependency is loaded only when the S3 provider is selected. Retained queued, processing, and failed jobs protect their staging objects from garbage collection.

When HTTP authentication is enabled, every endpoint except `/healthz` requires a Bearer token. Retrieval is scoped by the authenticated principal at both boundaries: owned document IDs are pushed into search, and returned candidates are rechecked against PostgreSQL before evidence is emitted. Job reads and mutations are scoped the same way.

The real MinIO suite is opt-in because it writes and deletes actual objects:

```bash
SMARTRAG_MINIO_E2E=1 \
SMARTRAG_MINIO_ENDPOINT=http://127.0.0.1:19000 \
SMARTRAG_MINIO_BUCKET=smart-rag-e2e \
SMARTRAG_MINIO_ACCESS_KEY=smart-rag-e2e \
SMARTRAG_MINIO_SECRET_KEY=smart-rag-e2e-secret \
bundle exec rspec spec/integration/minio_content_store_spec.rb
```

It verifies cross-instance storage, asynchronous worker materialization, reference lifecycle, real deletion, and failed-job GC protection. Run the real PostgreSQL HTTP isolation and idempotency checks with:

```bash
bundle exec rspec \
  spec/integration/media_tenant_isolation_spec.rb \
  spec/integration/media_p3_spec.rb
```

## Documentation Map

See `docs/DOCUMENTATION_INDEX.en.md` for a curated map of all docs, reading order, and maintenance notes.
Chinese version: `docs/DOCUMENTATION_INDEX.md`.

Other key documents:

- `docs/design.md` — System design
- `docs/API_DOCUMENTATION.md` — Detailed API docs
- `docs/SETUP_GUIDE.md` — Environment setup guide
- `docs/USAGE_EXAMPLES.md` — Usage examples
- `docs/Hybrid_Reranking.md` — Hybrid search & reranking details
- `docs/SmartChunking.md` — Smart chunking details
- `docs/MIGRATION_GUIDE.md` — Migration guide
- `docs/PERFORMANCE_GUIDE.md` — Performance optimization guide
- `ER-diagram.mmd` — ER diagram

## Notes

- Some legacy docs still contain older defaults (e.g. OpenAI references). Runtime truth is `config/smart_rag.yml`.

## License

MIT
