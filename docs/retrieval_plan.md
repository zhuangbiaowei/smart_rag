## 1. 目的

RetrievalPlan 用于把“本轮需要检索什么、怎么检索、取多少、如何控制噪声”表达为结构化对象，避免：
- 调用方隐式依赖 SmartRAG 内部策略（不可控）
- 多模式检索无法复现与调试（不可观测）
- 上下文装配缺少预算与多样性约束（易被噪声淹没）

---

## 2. 顶层结构

RetrievalPlan 是一个 JSON/Ruby Hash 对象（可序列化入日志）。

```json
{
  "version": "0.1",
  "request_id": "uuid",
  "purpose": "qa|continue_task|debug|summarize|research|other",
  "queries": [],
  "global_filters": {},
  "budget": {},
  "ranking": {},
  "output": {},
  "debug": {}
}
```

字段说明：

* `version`：协议版本（必填）
* `request_id`：调用方生成，用于贯穿日志与可追溯（建议必填）
* `purpose`：检索目的，用于策略默认值（可选）
* `queries`：检索 query 列表（必填，至少 1 条）
* `global_filters`：对所有 queries 生效的过滤（可选）
* `budget`：数量预算与多样性约束（可选但强烈建议）
* `ranking`：融合与重排设置（可选）
* `output`：返回内容控制（可选）
* `debug`：调试信息（可选）

---

## 3. queries（必填）

### 3.1 Query 对象

```json
{
  "text": "string",
  "mode": "exact|semantic|hybrid|relational|associative",
  "weight": 1.0,
  "filters": { },
  "hints": { }
}
```

字段说明：

* `text`：查询文本（必填）
* `mode`：

  * `exact`：关键词/短语精确查找（FTS/BM25）
  * `semantic`：语义召回（embedding）
  * `hybrid`：exact + semantic（由执行方融合）
  * `relational`：关联检索（实体/链接/任务链）
  * `associative`：联想检索（通常表示“扩展 query”，执行方应按策略调用 exact/semantic 再融合）
* `weight`：该 query 的相对权重（默认 1.0）
* `filters`：只对该 query 生效的过滤（覆盖/补充 global_filters）
* `hints`：提示执行策略的附加信息（可选）

> 建议：SmartBrain 的“联想”实现为生成多个 `associative` 或多条 `semantic/exact` 扩展 queries，而不是让执行方自由发挥。

### 3.2 queries 最小示例

```json
{
  "version": "0.1",
  "request_id": "c2b2f7d6-7c3b-4d53-8f8b-6f1f3a8c2a10",
  "purpose": "qa",
  "queries": [
    { "text": "OpenViking retrieval design", "mode": "hybrid", "weight": 1.0 }
  ]
}
```

### 3.3 queries（扩展/联想）示例

```json
{
  "version": "0.1",
  "request_id": "b7b1b1ce-2330-4f72-9f7b-92a6a1a2e12a",
  "purpose": "research",
  "queries": [
    { "text": "RAG memory runtime design", "mode": "hybrid", "weight": 1.0 },
    { "text": "MemGPT hierarchical memory", "mode": "semantic", "weight": 0.7 },
    { "text": "Letta archival memory blocks", "mode": "semantic", "weight": 0.7 },
    { "text": "context composer token budget diversity", "mode": "exact", "weight": 0.5 }
  ]
}
```

---

## 4. global_filters（可选）

对所有 queries 生效。执行方必须支持“只过滤不改变语义”的行为。

```json
{
  "document_ids": ["..."],
  "tag_ids": ["..."],
  "topic_ids": ["..."],
  "source_type": ["url","file","manual","memory_snapshot"],
  "source_uri_prefix": ["https://...", "file://..."],
  "language": ["zh","en"],
  "time_range": { "from": "2026-01-01T00:00:00Z", "to": "2026-02-20T00:00:00Z" }
}
```

说明：

* `document_ids/tag_ids/topic_ids`：知识库内过滤
* `source_type`：资源类型过滤（建议 SmartRAG 支持）
* `source_uri_prefix`：按 URI 前缀过滤（适合域名/路径范围）
* `language`：语言过滤（可选）
* `time_range`：时间过滤（可按 documents.created_at 或 sections.created_at 实现）

---

## 5. budget（可选但强烈建议）

```json
{
  "top_k": 30,
  "per_mode_k": { "exact": 10, "semantic": 10, "hybrid": 10, "relational": 10, "associative": 10 },
  "candidate_k": 200,
  "diversity": {
    "by_document": 3,
    "by_source": 10,
    "by_section": 1
  }
}
```

说明：

* `top_k`：最终返回条数
* `per_mode_k`：各模式配额（执行方可按存在的模式取 min）
* `candidate_k`：召回候选池规模（用于 rerank）
* `diversity`：多样性约束（避免单文档/单来源垄断）

> 实施建议：如果执行方不支持某一 diversity 维度，应忽略并在 explain 中声明。

---

## 6. ranking（可选）

用于约束融合与重排。

```json
{
  "fusion": { "method": "rrf|weighted_sum|none", "rrf_k": 60, "weights": { "exact": 1.0, "semantic": 1.0 } },
  "rerank": { "enabled": true, "model": "qwen3-reranker", "top_n": 50 },
  "tie_breaker": "recency|source_priority|none",
  "source_priority": { "url": 0.9, "file": 1.0, "manual": 0.8, "memory_snapshot": 0.7 }
}
```

说明：

* `fusion.method`：默认建议 `rrf`
* `rerank.enabled`：是否启用 reranker
* `tie_breaker`：分数相近时的决策
* `source_priority`：来源优先级（可选）

---

## 7. output（可选）

控制返回内容形态，便于 token 控制与调试。

```json
{
  "include_snippets": true,
  "snippet_policy": "l2|l1|l0|auto",
  "include_signals": true,
  "include_provenance": true,
  "include_raw": false,
  "max_snippet_chars": 800
}
```

说明：

* `snippet_policy`：建议未来支持 L0/L1/L2（如 OpenViking 分层）
* `max_snippet_chars`：用于截断（执行方应保证不超）

---

## 8. debug（可选）

```json
{
  "trace": true,
  "notes": "free text",
  "caller": { "app": "smart_bot", "session_id": "..." }
}
```

---

## 9. 执行方最低合规要求（SmartRAG/SmartBrain）

执行方至少要做到：

1. 支持 `queries.text + mode` 的基本执行（exact/semantic/hybrid 至少两种）
2. 支持 `top_k` 与基本 filters（document_ids/tag_ids/topic_ids）
3. 返回结果时能提供最少的 explain（见下）

建议执行方在返回 EvidencePack 时包含：

* `plan_id/request_id`
* `stats`（候选数、耗时、返回数）
* `explain`（融合方式、是否 rerank、忽略了哪些字段）

---

## 10. 变更策略

* v0.1：新增字段只能“可选”，不得破坏现有字段含义
* v0.x：执行方必须忽略未知字段并在 explain 中声明（可选）
* v1.0：如需破坏性变更，另起 major 版本并提供迁移说明

---

## 11. 当前实现状态（SmartRAG）

已支持：

* `queries.text + mode`：`exact/semantic/hybrid`
* `global_filters.document_ids/tag_ids/topic_ids/time_range/source_type/source_uri_prefix`
* `budget.top_k/candidate_k/per_mode_k`
* `budget.diversity.by_document/by_source`
* `output.include_snippets/include_signals/include_provenance/include_raw/max_snippet_chars`

部分支持：

* `queries.mode=relational/associative`：当前降级为 `hybrid`

未支持（会进入 `explain.ignored_fields`）：

* `budget.diversity.by_section`
