# Documentation Index

[中文版](DOCUMENTATION_INDEX.md)

This document provides a consolidated map of the current documentation set, including purpose, audience, and suggested reading order.

## Recommended Reading Path

1. `../README.en.md`  
   Project entry and quick start
2. `SETUP_GUIDE.md`  
   Detailed environment and deployment setup
3. `API_DOCUMENTATION.md`  
   API reference
4. `USAGE_EXAMPLES.md` + `../examples/README.md`  
   Practical patterns and runnable examples
5. `PERFORMANCE_GUIDE.md` and `Hybrid_Reranking.md`  
   Performance tuning and ranking strategy
6. `MIGRATION_GUIDE.md`  
   Upgrade and compatibility notes

## Document Catalog

| File | Language | Purpose | Primary Audience |
|---|---|---|---|
| `../README.md` | Chinese | Project overview, quick start, command entry | All users |
| `../README.en.md` | English | Project overview and quick start | English readers |
| `SETUP_GUIDE.md` | Chinese | Environment setup and deployment | DevOps / backend engineers |
| `API_DOCUMENTATION.md` | Chinese | API descriptions and examples | Integrators / backend developers |
| `USAGE_EXAMPLES.md` | English | End-to-end usage patterns and best practices | Application developers |
| `../examples/README.md` | English | Runnable script map and usage | New adopters |
| `PERFORMANCE_GUIDE.md` | English | Search and DB performance guidance | Performance engineers |
| `Hybrid_Reranking.md` | English | Hybrid retrieval and reranking notes | Search relevance engineers |
| `SmartChunking.md` | English | Chunking strategy details | Ingestion pipeline developers |
| `MIGRATION_GUIDE.md` | English | Version migration process | Maintainers |
| `../test/README.md` | Chinese | Test dataset notes | QA / developers |
| `../test/TEST_GUIDE.md` | Chinese | Manual testing scripts and scenarios | QA / developers |
| `design.md` | English | System design notes | Architects / maintainers |
| `requirements.md` | English | Requirement definition | Product / architecture reviewers |
| `FIX_SUMMARY.md` | English | Intermediate fix summary | Maintainers |
| `FIX_SUMMARY_COMPLETE.md` | English | Consolidated fix report | Maintainers |
| `todo.md` | English | Backlog and pending tasks | Maintainers |

## Gaps and Alignment Notes

- Some docs still use older defaults (for example OpenAI snippets). Runtime source of truth is `../config/smart_rag.yml`.
- Language coverage is currently uneven: some docs are Chinese-only, some are English-only. Add translated counterparts by priority.

## Maintenance Policy

- When API signatures change, update at least:
  - `../lib/smart_rag.rb`
  - `API_DOCUMENTATION.md`
  - `USAGE_EXAMPLES.md`
  - `../examples/*.rb`
- When default configuration changes, update at least:
  - `../.env.example`
  - `../config/smart_rag.yml`
  - `../README.md`
  - `../README.en.md`
