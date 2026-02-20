## 1. 目的

EvidencePack 用于将一次检索的结果，以**可复现、可解释、可融合**的方式返回给 SmartBrain，避免：
- 只返回片段文本，无法追溯来源与评分构成
- 多模式检索融合过程不可观测，难以调试/评估
- 跨源融合（memory vs resource）时缺少统一格式

EvidencePack 不包含“最终 prompt”，只包含候选证据与必要的元信息。

---

## 2. 顶层结构

```json
{
  "version": "0.1",
  "plan": { },
  "plan_id": "uuid",
  "request_id": "uuid",
  "generated_at": "2026-02-20T12:00:00Z",

  "evidences": [],
  "stats": { },
  "explain": { },
  "warnings": []
}
```

字段说明：

* `version`：协议版本（必填）
* `plan`：原始 RetrievalPlan（可选但强烈建议保留，用于复现）
* `plan_id`：执行方生成的唯一 id（建议必填）
* `request_id`：来自 RetrievalPlan.request_id（建议必填）
* `generated_at`：生成时间（必填）
* `evidences`：证据列表（必填，可能为空）
* `stats`：执行统计（候选数、耗时、返回数等）
* `explain`：融合/重排/过滤的解释信息（强烈建议）
* `warnings`：忽略字段、降级策略等提示（可选）

---

## 3. EvidenceItem 结构

```json
{
  "id": "string",
  "kind": "resource_section|resource_doc|memory_chunk|other",

  "document_id": "string",
  "section_id": "string",

  "title": "string",
  "source_uri": "string",
  "source_type": "url|file|manual|memory_snapshot|other",

  "snippet": "string",
  "snippet_policy": "l2|l1|l0|auto",
  "language": "zh|en|other",

  "signals": {
    "vector_score": 0.0,
    "vector_rank": 0,
    "fts_score": 0.0,
    "fts_rank": 0,
    "rrf_score": 0.0,
    "rerank_score": 0.0,
    "tag_score": 0.0,
    "topic_score": 0.0,
    "recency_score": 0.0
  },

  "provenance": {
    "mode": "exact|semantic|hybrid|relational|associative",
    "query_text": "string",
    "query_index": 0,
    "retrieved_at": "2026-02-20T12:00:00Z"
  },

  "metadata": {
    "chunk_index": 12,
    "offset_start": 1234,
    "offset_end": 1567,
    "page": 3,
    "section_title": "string"
  },

  "raw": {
    "content_ref": "section:l2",
    "content_hash": "sha256:...",
    "debug_payload": { }
  }
}
```

### 3.1 必填字段（v0.1 最低要求）

* `id`
* `source_uri`
* `snippet`
* `provenance.mode`
* `signals` 至少包含：`rrf_score`（若使用融合）或 `vector_score/fts_score` 之一
* `generated_at`（在顶层）

### 3.2 推荐字段

* `document_id/section_id`：用于去重与回源
* `signals` 全量：用于解释与回归评估
* `metadata`：用于展示与定位（标题、页码、chunk 位置）
* `plan`：用于复现

> 说明：如果某些字段后端暂不支持，应置空/省略，并在 `warnings` 或 `explain.ignored_fields` 中说明。

---

## 4. stats（统计）

```json
{
  "candidates": 200,
  "returned": 30,
  "took_ms": 128,
  "by_mode": {
    "exact": { "candidates": 50, "returned": 10 },
    "semantic": { "candidates": 100, "returned": 10 },
    "hybrid": { "candidates": 200, "returned": 30 }
  }
}
```

---

## 5. explain（解释）

```json
{
  "fusion": {
    "method": "rrf|weighted_sum|none",
    "rrf_k": 60,
    "weights": { "exact": 1.0, "semantic": 1.0 }
  },
  "rerank": { "enabled": true, "model": "qwen3-reranker", "top_n": 50 },
  "filters_applied": {
    "tag_ids": ["..."],
    "topic_ids": ["..."],
    "time_range": { "from": "...", "to": "..." }
  },
  "diversity": {
    "by_document": 3,
    "by_source": 10,
    "applied": true
  },
  "ignored_fields": [
    "global_filters.language not supported",
    "diversity.by_source not supported"
  ]
}
```

说明：

* `filters_applied`：最终实际生效的过滤条件（非常重要）
* `ignored_fields`：执行方未支持字段，必须显式说明，方便调用方调整策略

---

## 6. warnings（可选）

`warnings` 是字符串数组，用于快速提示调用方问题，例如：

* `time_range filter ignored due to missing created_at index`
* `rerank disabled because model not configured`

---

## 7. 去重与稳定性建议（给执行方）

为了让 SmartBrain 可靠装配上下文，SmartRAG（执行方）建议：

* `id` 稳定可重现（例如 `doc_id:section_id:chunk_index`）
* 对相同 section 的不同 query 命中：保留最高分，并在 provenance 中记录最强来源（或保留多个 provenance）
* `snippet` 应受 `output.max_snippet_chars` 约束，避免塞爆 token
* 返回顺序应是“最终排序结果顺序”（已融合/已 rerank）

---

## 8. 版本与兼容

* v0.1：新增字段仅可选；执行方忽略未知字段
* 如需破坏性变更，升级 major 版本并提供迁移说明

---

## 9. 当前实现状态（SmartRAG）

已实现（v0.1 最小闭环）：

* 顶层字段：`version/plan/plan_id/request_id/generated_at/evidences/stats/explain/warnings`
* `EvidenceItem` 关键字段：`id/document_id/section_id/source_uri/source_type/snippet/signals/provenance/metadata`
* `signals` 最小集合：
  * `vector_score/vector_rank`
  * `fts_score/fts_rank`
  * `rrf_score`
  * `rerank_score`
  * `tag_score/topic_score`（当前为占位分数）
* `explain`：`fusion/rerank/filters_applied/diversity/ignored_fields`

已知限制：

* `source_uri` 依赖文档元数据或文档记录；历史老数据可能为空
* `topic_score/tag_score` 目前未参与真实排序特征，仅用于字段对齐
