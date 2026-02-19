# SmartRAG

[中文 README](README.md)

SmartRAG is a Ruby-based hybrid RAG library that combines vector retrieval, full-text search, and topic/tag organization for document intelligence workflows.

## Overview

- Hybrid retrieval: vector + full-text + weighted fusion
- Document ingestion from local files and URLs
- Topic and tag management APIs
- Search logs and system statistics
- Runnable example scripts for quick onboarding

## Default Model Setup

Current defaults use local Ollama-compatible endpoints:

- Embedding model: `qwen3-embedding`
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

## Minimal Usage

```ruby
require "smart_rag"

config = SmartRAG::Config.load("config/smart_rag.yml")
client = SmartRAG::SmartRAG.new(config)

client.add_document("test/python_basics.md", generate_embeddings: true)
results = client.search("What is machine learning?", search_type: "hybrid", limit: 5)

puts results[:results].map { |r| r[:section_title] }
```

## Development Commands

- `bundle exec rspec`: run RSpec tests
- `ruby test/test_rag.rb`: run E2E script
- `bundle exec rake db:reset`: recreate database
- `gem build smart_rag.gemspec`: build gem package

## Project Structure

```text
lib/
  smart_rag.rb                 # Main API entry
  smart_rag/core/              # Core processing logic
  smart_rag/services/          # Search/tag/embedding services
config/                        # Runtime config files
db/                            # Migrations and seed SQL
examples/                      # Example programs
test/                          # Manual/E2E scripts + sample docs
spec/                          # RSpec tests
```

## Documentation Map

See `docs/DOCUMENTATION_INDEX.en.md` for a curated map of all docs, reading order, and maintenance notes.  
Chinese version: `docs/DOCUMENTATION_INDEX.md`.

## Notes

- Some legacy docs still contain older defaults (for example OpenAI references). Runtime truth is `config/smart_rag.yml`.

## License

MIT
