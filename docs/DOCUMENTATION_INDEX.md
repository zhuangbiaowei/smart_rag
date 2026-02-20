# 文档总览

[English Version](DOCUMENTATION_INDEX.en.md)

本文档用于统一梳理当前文档，说明用途、目标读者与推荐阅读顺序。

## 推荐阅读路径

1. `../README.md`  
   项目入口与快速启动
2. `SETUP_GUIDE.md`  
   环境与部署详细安装指南
3. `API_DOCUMENTATION.md`  
   API 参考说明
4. `USAGE_EXAMPLES.md` + `../examples/README.md`  
   实战用法与可运行示例
5. `PERFORMANCE_GUIDE.md` 与 `Hybrid_Reranking.md`  
   性能调优与排序策略
6. `MIGRATION_GUIDE.md`  
   版本迁移与兼容说明
7. `smartrag_improvement_plan.md` + `retrieval_plan.md` + `evidence_pack.md`  
   SmartRAG 重构计划与检索契约

## 文档目录梳理

| 文件 | 语言 | 用途 | 主要读者 |
|---|---|---|---|
| `../README.md` | 中文 | 项目概览、快速开始、命令入口 | 所有用户 |
| `../README.en.md` | 英文 | Project overview and quick start | English readers |
| `SETUP_GUIDE.md` | 中文 | 环境安装与部署 | DevOps / 后端工程师 |
| `API_DOCUMENTATION.md` | 中文 | API 说明与示例 | 接入开发者 |
| `USAGE_EXAMPLES.md` | 英文 | 端到端用法与最佳实践 | 应用开发者 |
| `../examples/README.md` | 英文 | 示例脚本导航与运行说明 | 新用户 |
| `PERFORMANCE_GUIDE.md` | 英文 | 搜索与数据库性能指南 | 性能优化工程师 |
| `Hybrid_Reranking.md` | 英文 | 混合检索与重排设计说明 | 搜索相关性工程师 |
| `SmartChunking.md` | 英文 | 分块策略说明 | 数据导入/切分开发者 |
| `MIGRATION_GUIDE.md` | 英文 | 版本迁移说明 | 维护者 |
| `smartrag_improvement_plan.md` | 中文 | 1-2 天改进执行计划 | 维护者/负责人 |
| `retrieval_plan.md` | 中文 | RetrievalPlan 契约规范 | SmartBrain/检索接入开发者 |
| `evidence_pack.md` | 中文 | EvidencePack 契约规范 | SmartBrain/检索接入开发者 |
| `../test/README.md` | 中文 | 测试文档数据集说明 | QA / 开发者 |
| `../test/TEST_GUIDE.md` | 中文 | 手工测试脚本与场景说明 | QA / 开发者 |
| `design.md` | 英文 | 系统设计说明 | 架构/维护者 |
| `requirements.md` | 英文 | 需求定义 | 产品/架构评审 |
| `FIX_SUMMARY.md` | 英文 | 阶段性修复总结 | 维护者 |
| `FIX_SUMMARY_COMPLETE.md` | 英文 | 完整修复报告 | 维护者 |
| `todo.md` | 英文 | 待办与规划 | 维护者 |

## 当前缺口与对齐说明

- 部分文档仍使用旧默认值示例（如 OpenAI）。运行时配置以 `../config/smart_rag.yml` 为准。
- 当前文档语言分布不均：部分仅中文、部分仅英文。后续可按优先级补齐对应翻译版本。

## 文档维护建议

- API 发生变更时，至少同步更新：
  - `../lib/smart_rag.rb`
  - `API_DOCUMENTATION.md`
  - `USAGE_EXAMPLES.md`
  - `../examples/*.rb`
- 默认配置调整时，至少同步更新：
  - `../.env.example`
  - `../config/smart_rag.yml`
  - `../README.md`
  - `../README.en.md`
