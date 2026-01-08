# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains the SmartRAG library code. Core logic lives under `lib/smart_rag/core`, and services under `lib/smart_rag/services`.
- `test/` holds runnable scripts (e.g., `test_rag.rb`, `import_doc.rb`) and sample markdown documents used for manual testing.
- `spec/` contains RSpec tests (when present).
- `config/` stores application configuration, including database and full-text search settings.
- `db/` contains SQL scripts and database-related artifacts.

## Build, Test, and Development Commands
- `bundle install` installs Ruby dependencies.
- `ruby test/import_doc.rb import` imports test documents into the local database.
- `ruby test/test_rag.rb` runs the end-to-end RAG tests in `test/`.
- `bundle exec rspec` runs any RSpec tests in `spec/`.

## Coding Style & Naming Conventions
- Ruby files use 2-space indentation.
- Class/module names use `CamelCase`; methods and files use `snake_case`.
- Keep public API methods in `lib/smart_rag.rb` small and delegate to `core/` or `services/`.

## Testing Guidelines
- End-to-end checks are in `test/test_rag.rb`; run after reindexing or data changes.
- RSpec tests (when present) should live in `spec/` and follow `*_spec.rb` naming.
- If a test depends on data, ensure `test/import_doc.rb` has been run.

## Commit & Pull Request Guidelines
- Git history shows short messages like `fix bug`; there is no strict convention yet.
- Use concise, imperative commit messages (e.g., `fix fulltext indexing`).
- PRs should include: a short summary, steps to verify, and any data/setup notes.

## Security & Configuration Tips
- Database credentials live in `config/smart_rag.yml` or environment variables (see `config/`).
- Avoid committing API keys; use `.env.example` as the template.
