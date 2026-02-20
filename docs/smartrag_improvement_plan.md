# SmartRAG 改进计划（1-2 天冲刺版）

## 1. 目标与范围

本计划目标是在 **1-2 天内**完成 SmartRAG 与 SmartBrain 的契约化集成最小闭环，并同步补齐关键可观测与索引治理能力。

本次改进聚焦：

- 新增统一入口：`retrieve(plan)`（`RetrievalPlan -> EvidencePack`）
- 统一输出：`EvidencePack v0.1`（含 signals/stats/explain）
- 兼容现有 `search(...)`（不破坏旧调用）
- 补齐核心可观测：`search_logs` 记录 `plan_json + stats + explain`
- 落地最小索引治理：幂等导入与重建入口

不在本次范围：

- 对话事件管理、记忆抽取、上下文编排、Agent loop（归属 SmartBrain/SmartBot/SmartAgent）
- 大规模 schema 重构
- L0/L1/L2 全量能力落地（仅预留字段与策略）

---

## 2. 交付物

- `smart_rag/docs/retrieval_plan.md`（对齐实现，必要时补充“已支持/未支持”）
- `smart_rag/docs/evidence_pack.md`（对齐实现，必要时补充“最低合规字段”）
- `smart_rag/docs/smartrag_improvement_plan.md`（本文档）
- `lib/smart_rag/retrieve.rb`（或等价入口模块）
- `spec/retrieve_spec.rb`（关键路径测试）
- `CHANGELOG.md`（新增接口、兼容策略、已知限制）

---

## 3. 执行节奏（非按周，按里程碑）

### M1：契约主链路打通（Day 1，上半天）

目标：让 SmartBrain 可稳定调用 `retrieve(plan)` 并拿到结构化结果。

任务：

1. 新增 `retrieve(plan)` 入口，接收 `RetrievalPlan v0.1`。
2. 支持最小 `queries` 执行：`exact/semantic/hybrid`（至少两种模式可用）。
3. 结果统一封装为 `EvidencePack v0.1` 顶层结构：
   - `version`
   - `plan_id`
   - `request_id`
   - `generated_at`
   - `evidences`
   - `stats`
   - `explain`
   - `warnings`（可选）
4. 保留 `search(...)`，内部逐步复用新执行路径。

验收标准：

- 可用 `RetrievalPlan` 直接调用 `retrieve(plan)`。
- 响应结构符合 `EvidencePack` 最低要求。
- 不影响现有 `search(...)` 调用。

---

### M2：可解释与可观测补齐（Day 1，下半天）

目标：结果可复现、可解释、可调试。

任务：

1. 为每条 evidence 增加 `signals` 最小集合：
   - `vector_score/vector_rank`
   - `fts_score/fts_rank`
   - `rrf_score`
   - `rerank_score`（模型未启用时可空或置默认）
2. 输出 `provenance`：
   - `mode`
   - `query_text`
   - `query_index`
   - `retrieved_at`
3. 完成 `stats` 与 `explain`：
   - `candidates/returned/took_ms`
   - `fusion`、`rerank`、`filters_applied`
   - `ignored_fields`（未支持字段必须明示）
4. 将 `plan_json + stats/explain` 写入 `search_logs`。

验收标准：

- 任一结果都可追溯“来自哪个 query、以何模式命中、融合信号是什么”。
- 日志可用于离线复盘同一次检索过程。

---

### M3：过滤、预算、多样性与稳定性（Day 2，上半天）

目标：把噪声控制能力落到执行层，不依赖调用方隐式技巧。

任务：

1. 支持 `global_filters` 最小集：
   - `document_ids`
   - `tag_ids`
   - `topic_ids`
   - `source_type`
   - `time_range`（若暂不支持，显式写入 `ignored_fields`）
2. 支持 `budget` 最小集：
   - `top_k`
   - `candidate_k`
   - `per_mode_k`（按已启用模式截断）
3. 支持最小多样性约束：
   - `diversity.by_document`
4. `output` 最小支持：
   - `include_snippets`
   - `include_signals`
   - `max_snippet_chars`

验收标准：

- 同一 query 在设置预算与多样性后，结果集中度明显降低（避免单文档垄断）。
- 不支持字段会被显式告知，不出现“静默忽略”。

---

### M4：索引治理与收口发布（Day 2，下半天）

目标：避免长期运行后的索引漂移和重复污染，并完成发布闭环。

任务：

1. 幂等导入最小策略：
   - 引入/启用 `content_hash`
   - 同源同内容避免重复写入（`source_uri + content_hash`）
2. 提供重建入口：
   - `rebuild_fts(document_id=nil)`
   - `rebuild_embeddings(document_id=nil)`
   - `reindex(document_id=nil)`
3. 文档与变更收口：
   - 更新 `CHANGELOG.md`
   - 在文档中标注已实现与待实现项（如 `tag_score/topic_score` 参与排序）

验收标准：

- 重复导入不会持续膨胀索引。
- 可对单文档或全量执行重建。
- 变更说明清晰，可被 SmartBrain 团队直接消费。

当前进展补充（已落地）：

- 已新增 `source_documents.source_type/source_uri/content_hash` 与索引
- 已提供 `rake db:backfill_source_fields` 回填任务
- 已提供轻量单测入口（不依赖测试库连接）用于 `retrieve/reindex` 核心行为验证

---

## 4. 最小实现清单（MVP Done Definition）

满足以下条件即判定本轮完成：

1. `retrieve(plan)` 可用，`search(...)` 保持兼容。
2. `EvidencePack` 输出包含最低必需字段与 signals。
3. `exact/semantic/hybrid` 至少两种模式稳定可用（推荐三种都可用）。
4. `search_logs` 可记录 `request_id + plan_json + stats + explain`。
5. 至少一组集成测试覆盖：
   - 单 query hybrid
   - 多 query 融合
   - filters + budget + diversity
   - unknown/unsupported 字段处理（`ignored_fields`）

---

## 5. 风险与缓解

风险 1：`time_range/language/source_uri_prefix` 等字段短期无法完全支持  
缓解：严格走 `ignored_fields` 与 `warnings`，不做静默降级。

风险 2：reranker 模型不可用导致结果波动  
缓解：`rerank.enabled=false` 自动降级，`explain` 明确记录。

风险 3：多 query 融合后结果重复或单源聚集  
缓解：先做稳定去重（按 `document_id/section_id`）+ `diversity.by_document`。

风险 4：1-2 天冲刺导致文档与实现偏差  
缓解：以测试快照校验 `RetrievalPlan` 输入与 `EvidencePack` 输出结构。

---

## 6. 执行顺序（建议）

1. 先打通 `retrieve(plan)` 与 `EvidencePack` 骨架（M1）。
2. 再补 signals/explain/logging（M2）。
3. 接着补 filters/budget/diversity（M3）。
4. 最后完成索引治理与文档收口（M4）。

这个顺序能确保即使 Day 2 出现意外，Day 1 结束时仍有可集成、可调试的主链路成果。

---

## 7. 后续增量（不阻塞本轮）

- `tag_score/topic_score` 从“占位字段”升级为真实排序特征
- `source_priority/tie_breaker` 精细策略
- L0/L1/L2 分层 snippet 策略（`snippet_policy` 全实现）
- 更完善的离线评测集与回归基线（NDCG/Recall/Latency）
