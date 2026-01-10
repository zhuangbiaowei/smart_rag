# RAGFlow 多路召回与重排序（Hybrid Search & Reranking）技术介绍

在 RAGFlow 中，多路召回（Multi-path Retrieval）与重排序（Reranking）技术共同构成了其高精度检索的核心架构，旨在解决单一检索方式在复杂查询下容易出现的“搜不准、搜不全”问题。以下是 2026 年初该技术的详细解读：

1. 多路召回技术：确保“广而全”

RAGFlow 采用双路混合检索架构，利用不同维度的“筛子”同时在海量文档中筛选候选结果。 
全文检索（关键词通路）：
核心算法：通常基于 BM25 算法。
优势：擅长精准匹配缩写、产品型号、专业术语或姓名。例如搜索“R1-750”，全文检索能精准锁定包含该特定编号的文档。
向量检索（语义通路）：
核心算法：利用 Embedding 模型（如 BGE 或 OpenAI 兼容模型）将文本转化为高维向量。
优势：理解用户意图，即使问题中没有原词，也能找到意思相近的内容。例如用户问“如何理财”，系统能检索到包含“资产配置”或“储蓄方案”的片段。
混合融合（RRF）：
系统使用 倒数排名融合（Reciprocal Rank Fusion, RRF） 等算法将两路结果合并，初步平衡关键词匹配和语义相关性的得分。 

2. 重排序技术：确保“精而准”

多路召回虽然覆盖面广，但往往会混入不相关的噪音。RAGFlow 引入重排序（Reranking）阶段，对初步选出的 Top-K 候选片断进行“二次打分”。 
级联式重排序策略：
交叉编码器（Cross-Encoder）：这是重排序的核心模型（如 bge-reranker-v2-m3）。与简单的向量相似度不同，它会将查询（Query）和文档（Document）同时输入模型，捕捉更细微的语义匹配关系。
上下文长度优势：截至 2026 年，其主流重排序模型已支持最高 8192 tokens 的上下文，能够处理更长的文档片段而不会丢失关键信息。
多模型集成：
RAGFlow 支持集成多种顶级重排序器，包括 Cohere Rerank、Jina Reranker 以及开源的 BGE 系列。2026 年甚至支持通过 vLLM 托管这些重排序模型以获得更高的推理效率。 

3. 技术核心优势

首条命中率提升：通过先“广搜”再“精排”，显著提高了首个召回片段的相关性，这对于 LLM 减少幻觉至关重要。
结构化数据亲和：针对 CSV/JSON 等缺乏自然语言语义的结构化数据，多路召回中的关键词通路能补足传统向量检索的短板。
可追溯性：重排序后的高分片段会与原文位置绑定，在 UI 界面上直接展示为高亮引用，保证了 AI 回答的“有据可查”。 
通过这种双引擎驱动 + 深度精排的模式，RAGFlow 能够将检索准确率从初级 RAG 的约 60% 提升至 90% 以上。

# 多路召回与重排序设计方案

  1) Hybrid Search：多路召回 + 融合

  - 入口：rag\nlp\search.py 的 Dealer.search()
      - 文本召回：FulltextQueryer.question() 生成 MatchTextExpr（BM25/查询字符串）并扩展同义词与细粒度 token。
          - 参考：rag\nlp\query.py
      - 向量召回：get_vector() 生成 MatchDenseExpr，向量字段命名 q_{dim}_vec。
          - 参考：rag\nlp\search.py
      - 融合：FusionExpr("weighted_sum", {"weights":"0.05,0.95"})，文本/向量权重融合。
          - 参考：rag\nlp\search.py
  - 数据库层执行：
      - OpenSearch：使用 query_string + knn，并用 FusionExpr 的权重调整 boost。
          - 参考：rag\utils\opensearch_conn.py
      - OB/Infinity 等：由连接器实现融合查询与归一化，Infinity 会归一化两路得分，后续无需再 rerank。
          - 参考：rag\nlp\search.py 中 settings.DOC_ENGINE_INFINITY 分支

  2) Rerank：两种路径

  - 内置 rerank（无外部模型）：
      - Dealer.rerank() 调用 FulltextQueryer.hybrid_similarity()
      - 得分 = token_similarity * tkweight + vector_similarity * vtweight + rank_feature
      - token_similarity 对内容 tokens + 标题/重要关键词加权（title2，important5，question*6）。
      - 参考：rag\nlp\search.py, rag\nlp\query.py
  - 外部 rerank 模型：
      - Dealer.rerank_by_model() 使用 reranker 输出向量得分，混合 token 相似度。
      - rerank 模型适配统一接口：similarity(query, texts)。
      - 参考：rag\nlp\search.py, rag\llm\rerank_model.py

  3) 排序增强：rank_feature（Pagerank / 标签）

  - rank_feature 引入 pagerank 与标签相关性加权。
  - _rank_feature_scores() 对标签向量与 query 标签做相似度，叠加 pagerank。
  - 参考：rag\nlp\search.py, rag\utils\opensearch_conn.py

  4) 流程细节

  - 再排序池大小：RERANK_LIMIT 固定到 64 的倍数分页，以扩大 rerank 范围。
      - 参考：rag\nlp\search.py
  - 失败回退：如果融合查询结果为空，降低 min_match、提高 similarity threshold 再试。
      - 参考：rag\nlp\search.py

  Ruby 复刻设计方案（详细）

  A. 模块划分

  - HybridSearch::QueryBuilder
      - 构造全文检索查询 + 同义词扩展 + token 权重。
      - 接口：build_text_query(question, min_match) → MatchTextExpr + keywords。
      - 参考：rag\nlp\query.py
  - HybridSearch::Embedding
      - encode_queries(text) → vector
      - 统一向量字段名：q_#{dim}_vec。
  - HybridSearch::Fusion
      - 表示融合策略：weighted_sum，保存权重。
      - 参考：common\doc_store\doc_store_base.py
  - HybridSearch::DocStoreAdapter
      - search(select_fields, filters, match_exprs, order_by, limit, offset, rank_feature)
      - 提供 OpenSearch/PG/OB/自研引擎适配。
  - HybridSearch::Reranker
      - rerank_by_model：外部模型返回相似度。
      - rerank_by_hybrid：token+vector 混合。
  - HybridSearch::Retriever
      - orchestrator：负责 recall → rerank → filtering → pagination。

  B. 核心数据结构

  - MatchTextExpr, MatchDenseExpr, FusionExpr（对齐 common\doc_store\doc_store_base.py）
  - SearchResult：total, ids, fields, query_vector, highlight, aggs

  C. 召回策略（Hybrid Search）

  1. 构建全文查询：
      - 英文：词权重 + 词邻近短语（bigram boost）。
      - 中文：分词 + 同义词 + fine-grained token。
  2. 构建向量查询：q_{dim}_vec + topk + similarity_threshold
  3. 组装 FusionExpr：默认 "0.05,0.95"（文本/向量）
  4. 交给 DocStoreAdapter 执行。

  D. Rerank 策略

  - 如果配置 rerank_model：
      - score = tkweight * token_similarity + vtweight * model_score + rank_feature
  - 否则：
      - score = tkweight * token_similarity + vtweight * vector_similarity + rank_feature
  - tkweight = 1 - vector_similarity_weight（配置默认 0.3）
  - rank_feature 依赖 pagerank / tag_vector（若存在）。

  E. 评分细节复刻

  - token_similarity：
      - 使用 term-weight 计算 query tokens 与 doc tokens 的重合度。
      - doc tokens= content_ltks + title_tks*2 + important_kwd*5 + question_tks*6
  - vector_similarity：
      - cosine similarity of query_vector vs doc_vector。
  - rank_feature：
      - pagerank + 标签向量相似度（可按需求保留）。

  F. 分页与 rerank pool

  - 先取大范围 RERANK_LIMIT（推荐 64 的倍数）
  - rerank 后再分页
  - 避免直接分页导致 rerank “局部最优”。

  G. Ruby 伪代码

  def retrieve(question, page, page_size, topk:, similarity:, vec_weight:, rerank_model: nil)
    text_expr, keywords = QueryBuilder.build_text_query(question, min_match: 0.3)
    dense_expr = Embedding.match_dense(question, topk: topk, similarity: similarity)

    fusion = FusionExpr.new("weighted_sum", topk, weights: "0.05,0.95")
    match_exprs = [text_expr, dense_expr, fusion]

    pool = docstore.search(fields, filters, match_exprs, limit: rerank_limit, offset: page_offset)

    scores = if rerank_model
      Reranker.rerank_by_model(rerank_model, pool, question, tkweight: 1-vec_weight, vtweight: vec_weight)
    else
      Reranker.rerank_by_hybrid(pool, question, tkweight: 1-vec_weight, vtweight: vec_weight)
    end

    ranked = pool.sort_by { |doc| -scores[doc.id] }
    paginate(ranked, page, page_size)
  end

  H. 配置参数建议

  - vector_similarity_weight（默认 0.3）
  - topk（召回池大小）
  - similarity_threshold（向量召回阈值）
  - rerank_model_id（可选）
  - rank_feature（pagerank/tag_fea 权重）

  复刻重点与注意事项

  - 若底层引擎能做融合归一化（类似 Infinity），可跳过自定义 rerank。
      - 参考：rag\nlp\search.py 对 Infinity 的分支判断。
  - 不同引擎的融合实现差异较大（OpenSearch 用 knn + query_string + boost），建议先实现一个“逻辑融合 + 本地 rerank”的通用路径，再做引擎级融合优化。
  - rank_feature（pagerank/tag_fea）是 RAGFlow 的额外增益项，若没有对应特征可直接忽略或留接口。