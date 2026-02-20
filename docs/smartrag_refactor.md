## 1. 目标与边界

### 1.1 目标
SmartRAG 的职责应当被明确为：

- **资源导入与索引**：文档/URL 导入、分块、embedding、FTS（Postgres tsvector/pg_jieba）、元数据管理
- **多模式检索**：exact / semantic / hybrid（向量 + FTS + 融合）
- **统一证据输出**：输出结构化 `EvidencePack` 供 SmartBrain 做上下文装配
- **可观测**：记录检索计划、融合信号、结果解释，便于调试与评估
- **可重建**：索引可重建（embedding/FTS），内容是真相

### 1.2 边界（SmartRAG 不做什么）
SmartRAG **不负责**：

- 对话事件（turn/tool call）存储与管理
- 记忆抽取（profile/preferences/entities/events/tasks/decisions）
- 上下文编排（token 预算、摘要、历史选择）
- Agent loop / 工具编排 / MCP

上述能力属于 SmartBrain / SmartBot / SmartAgent。

---

## 2. 现状与集成痛点

> 你现有 SmartRAG 已具备：pgvector + FTS + RRF 融合、标签/主题、日志等。但为了与 SmartBrain 形成「契约式」集成，需要补齐：

1. **检索入口表达能力不足**  
   目前 `search_type: vector/fulltext/hybrid` 能选模式，但 SmartBrain 需要表达：多 query、每路预算、过滤、去重/多样性、是否 rerank、返回信号等。

2. **输出缺乏“检索信号（signals）”**  
   SmartBrain 要做跨源融合（memory + resources）、上下文预算装配、结果解释，需要看到每条 evidence 的来源与分数构成（vector/fts/rrf/rerank/tag/topic）。

3. **索引维护与幂等导入不足**  
   SmartBrain 会不断把“记忆快照/摘要/会议纪要/网页快照”写入资源库；缺少幂等与重建会导致噪声膨胀与索引漂移。

---

## 3. 改造范围（MVP -> 完整版）

### 3.1 MVP（建议优先完成：1~2 个迭代）

#### A) 新增结构化检索入口：`retrieve(plan)`
新增统一入口（内部可复用现有 search/hybrid 逻辑）：

```ruby
SmartRAG.retrieve(plan: RetrievalPlan) => EvidencePack
````

**RetrievalPlan（Ruby Hash / JSON）**

```json
{
  "queries": [
    {
      "text": "…",
      "mode": "exact|semantic|hybrid",
      "weight": 1.0,
      "filters": { "tag_ids": [], "topic_ids": [] }
    }
  ],
  "global_filters": {
    "tag_ids": [],
    "topic_ids": [],
    "document_ids": [],
    "source_type": ["url", "file", "manual", "memory_snapshot"],
    "time_range": { "from": "2026-01-01T00:00:00Z", "to": "2026-02-19T00:00:00Z" }
  },
  "budget": {
    "top_k": 30,
    "per_mode_k": { "exact": 10, "semantic": 10, "hybrid": 10 },
    "diversity": { "by_document": 3, "by_source": 10 }
  },
  "rerank": { "enabled": true, "model": "qwen3-reranker", "top_n": 30 },
  "return": { "include_signals": true, "include_snippets": true }
}
```

> 说明：`queries` 用于表达 **联想/扩展 query**（由 SmartBrain 生成），SmartRAG 不需要知道“为什么扩展”，只执行计划。

#### B) 统一输出结构：`EvidencePack`

SmartRAG 的输出应当满足：可复用、可观测、可再融合。

**EvidencePack（JSON 形态）**

```json
{
  "plan_id": "uuid",
  "evidences": [
    {
      "document_id": "…",
      "section_id": "…",
      "snippet": "…",
      "metadata": { "title": "…", "source_uri": "…" },
      "signals": {
        "vector_score": 0.12,
        "vector_rank": 3,
        "fts_score": 0.41,
        "fts_rank": 1,
        "rrf_score": 0.032,
        "rerank_score": 0.88,
        "tag_score": 0.2,
        "topic_score": 0.0
      },
      "provenance": { "mode": "hybrid", "query_text": "…", "retrieved_at": "…" },
      "raw": { "content_ref": "section:l2" }
    }
  ],
  "stats": { "candidates": 200, "returned": 30, "took_ms": 128 },
  "explain": { "fusion": "RRF", "rerank": true }
}
```

#### C) 结果信号可观测（signals）

MVP 至少提供：

* `vector_rank/vector_score`
* `fts_rank/fts_score`
* `rrf_score`
* `rerank_score`（可选）
* `tag_score/topic_score`（先保留字段，MVP 可为 0）

#### D) 兼容现有 API

* 现有 `search(...)` 保留为简化接口；
* 新增 `retrieve(plan)` 面向 SmartBrain；
* `search` 内部可调用 `retrieve`（或相反），逐步统一实现。

---

### 3.2 完整版（SmartBrain 上线后逐步演进）

#### E) 标签/主题第三路融合（不是仅过滤）

让 tags/topics 参与排序信号：

* `tag_score/topic_score` 进入融合加权或 rerank features（如果 reranker 支持 feature 拼接则更好）

#### F) 索引维护能力

新增维护命令/接口：

* `rebuild_fts(document_id=nil)`
* `rebuild_embeddings(document_id=nil)`
* `reindex(document_id=nil)`（组合）
* `dedupe_by_content_hash`（幂等导入）

#### G) L0/L1/L2 层（与 OpenViking 思路兼容，可选）

* L2：原始 section 内容
* L1：overview（中等摘要+导航）
* L0：abstract（极短摘要，召回友好）

SmartRAG 可先只存 L2，后续逐步补齐 L0/L1（可由 SmartBrain 或 SmartRAG 生成）。

---

## 4. 数据结构调整建议（最小破坏）

> 在不大改既有 schema 的前提下，建议增补：

### 4.1 documents

* `source_type`：url/file/manual/memory_snapshot
* `source_uri`：统一 URI（用于 provenance 与去重）
* `content_hash`：幂等导入（URL 内容 hash / 文件 hash）
* `updated_at`：用于判断增量重建

### 4.2 sections

* `layer`：L0/L1/L2（可选）
* `summary`：用于 snippet 输出（可选）
* `metadata(jsonb)`：标题、页码、语言、代码语言、chunker 参数等

### 4.3 search_logs

* `plan_json`：保存 RetrievalPlan
* `signals_json`：保存统计与融合信号摘要（便于回归对比）

---

## 5. 与 SmartBrain 的契约（强约束）

* SmartBrain **只**通过 `retrieve(plan)` 调用 SmartRAG（避免隐式策略）
* SmartRAG **只**返回 `EvidencePack`（不返回最终 prompt）
* SmartBrain 负责：跨源融合（memory vs resource）、最终 rerank（可选）、上下文装配（token 预算）

---

## 6. 交付物清单（SmartRAG）

* `docs/retrieval_plan.md`：RetrievalPlan schema 与示例
* `docs/evidence_pack.md`：EvidencePack schema 与字段说明
* `lib/smart_rag/retrieve.rb`：新入口（或模块）
* `spec/retrieve_spec.rb`：关键路径测试
* `CHANGELOG.md`：新增接口与兼容策略说明

---

## 7. 里程碑与验收标准

### MVP 验收

* 能以 RetrievalPlan 调用 `retrieve(plan)`
* 返回 EvidencePack（含 signals）
* Hybrid/Exact/Semantic 三模式可用（至少 two modes）
* search_logs 记录 plan + stats + explain

### 完整版验收

* 幂等导入生效（相同 hash 不重复污染库）
* 索引重建命令可用
* tags/topics 对排序有显式贡献
* L0/L1/L2 支持（可选）