# SmartRAG Examples

These examples are extracted and organized from `docs/USAGE_EXAMPLES.md`.

## Prerequisites

1. Install dependencies:
   - `bundle install`
2. Configure environment variables (or rely on defaults in `examples/common.rb`):
   - `SMARTRAG_DB_HOST`
   - `SMARTRAG_DB_NAME`
   - `SMARTRAG_DB_USER`
   - `SMARTRAG_DB_PASSWORD`
   - `OPENAI_API_KEY`
3. Ensure your database is migrated and has test data if needed.

## Run Examples

- Quick start:
  - `ruby examples/01_quick_start.rb`
- Document management:
  - `ruby examples/02_document_management.rb test/python_basics.md`
  - Optional delete demo:
  - `DELETE=1 ruby examples/02_document_management.rb test/python_basics.md`
- Search operations:
  - `ruby examples/03_search_operations.rb`
- Topics and tags:
  - `ruby examples/04_topics_and_tags.rb`
- Advanced patterns:
  - `ruby examples/05_advanced_patterns.rb`
- Error handling and retry:
  - `ruby examples/06_error_handling_and_retry.rb`

## Mapping To `docs/USAGE_EXAMPLES.md`

- `01_quick_start.rb`: Quick Start
- `02_document_management.rb`: Document Management
- `03_search_operations.rb`: Search Operations
- `04_topics_and_tags.rb`: Research Topic Management + Tag Management
- `05_advanced_patterns.rb`: Advanced Usage Patterns + Q&A + Caching
- `06_error_handling_and_retry.rb`: Error Handling + Retry Logic
- `common.rb`: shared setup/config/logging utilities
