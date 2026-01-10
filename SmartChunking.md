# RAGFlow SmartChunking 技术介绍

RAGFlow 的智能切片（Smart Chunking）技术是其区别于传统 RAG 框架的核心竞争力。截至 2026 年，该技术已演进为一套基于“深度文档理解”的体系化方案，旨在解决“垃圾输入导致垃圾输出（GIGO）”的行业痛点。 

以下是 RAGFlow 智能切片技术的详细介绍：

1. 技术核心：基于布局的语义分割

传统的 RAG 框架通常采用“固定字符数”或“简单递归”切片，这往往会切断段落或表格的语义。RAGFlow 引入了 DeepDoc 引擎，通过以下步骤实现智能切片： 
视觉布局分析 (Visual Layout Analysis)：利用视觉深度学习模型识别文档中的标题、段落、列表、表格及图片位置。
物理到逻辑的转换：不仅提取文本，更理解“什么是标题”、“什么是对应的正文”，确保切片边界严格遵循文档的逻辑结构。 

2. 场景化解析模板（Template-based Chunking）

RAGFlow 针对不同格式的文档提供了 10 余种专用解析器，确保每类文档都能按最优逻辑切分： 
General（通用模式）：适用于一般文章，按段落和标题层次切分。
Manual（手册模式）：专为技术说明书设计，能够关联标题与多级步骤，保持上下文连贯。
Table（表格模式）：自动重构表格结构，将复杂的行列关系转化为可供 LLM 理解的 Markdown 或 HTML 格式。
Paper（论文模式）：识别摘要、引文、图表说明，过滤掉页眉页脚等干扰信息。
Laws/Finance（法律/金融）：精准识别条款编号和报表勾稽关系。 

3. 先进算法加持

在 2026 年的版本中，RAGFlow 结合了多项前沿算法优化检索性能：
语义张力检测（Semantic Tension Awareness）：动态感知语义转折点，避免在话题切换处进行错误分割。
RAPTOR（递归摘要树）：对于超长文档，系统会递归地对切片进行聚类并生成摘要，构建层级索引，解决跨切片的全局性提问。
父子切片（Parent-Child Chunking）：检索时通过小的子切片提高匹配精度，回答时则通过父切片提供更完整的背景上下文。 

4. 独特优势：可解释性与可视化

解析过程透明化：RAGFlow 提供可视化界面，允许用户查看文档是如何被“切碎”的，并支持手动微调分块策略。
精准溯源：在最终生成的回答中，每个引用都能精准定位到原始 PDF 中的具体矩形区域，而非仅仅给出一个模糊的文档 ID。 
通过这些技术，RAGFlow 的智能切片不仅提高了检索召回率，还显著减少了模型因上下文缺失而产生的幻觉问题。
  
# SmartChunking 设计方案

  以下方案紧贴 RAGFlow 的逻辑，但用 Ruby 可实现的模块化结构组织。

  1) 模块划分

  - SmartChunking::Parser
    负责不同文件类型抽取：文本行、段落、布局信息、表格、图片引用。
      - 参考入口：rag\app\book.py, rag\app\manual.py, rag\app\paper.py, rag\app\laws.py
  - SmartChunking::StructureDetector
    标题/层级检测、TOC/outline 辅助识别、bullet 模式匹配。
      - 参考：rag\nlp\__init__.py 的 BULLET_PATTERN、bullets_category、title_frequency
  - SmartChunking::Merger
    提供 tree_merge, hierarchical_merge, naive_merge 等合并策略。
      - 参考：rag\nlp\__init__.py
  - SmartChunking::MediaContext
    表格/图片 chunk 上下文补齐。
      - 参考：rag\nlp\__init__.py 的 attach_media_context
  - SmartChunking::Tokenizer
    统一 token 计数、tokenize/fine-grained tokenize。
      - 参考：rag\nlp\__init__.py 的 tokenize, num_tokens_from_string（common\token_utils）
  - SmartChunking::Pipeline
    根据文档类型选择策略；输出 chunk 列表。

  2) 数据结构设计

  - Section

    text: String
    layout: String?        # "title"/"text"/"head" 等
    position: [pn, x1, x2, y1, y2]? # 可选
  - Chunk

    text: String
    image: Image?          # or image_id
    doc_type: "text"|"table"|"image"
    positions: []          # 保留布局 tags 或 box
    context_above: String?
    context_below: String?
    metadata: { ... }      # 文档名、标题 tokens、important_kwd 等

  3) 标题/层级检测（核心）

  - Bullet 模式表：复刻 BULLET_PATTERN（中英文数字、章/节/条、Markdown 标题等）。
      - 参考：rag\nlp\__init__.py 的 BULLET_PATTERN
  - bullets_category(sections)
    统计哪组模式命中最多，选为当前文档 bullet 风格。
  - title_frequency(bull, sections)
    在所有段落中计算“最常见标题级别”，作为 pivot level（论文/手册使用）。
      - 参考：rag\nlp\__init__.py 的 title_frequency

  4) 层级合并策略

  - tree_merge（法规类）
      - 将段落映射到等级（标题/正文），构建树（Node）后截断深度。
      - depth=2 更适合法规层级。
      - 参考：rag\nlp\__init__.py 的 tree_merge, Node + rag\app\laws.py
  - hierarchical_merge（书籍类）
      - 先分类所有段落索引到各级别数组，再从高到低组合成块。
      - depth=5 适合长书的层级。
      - 参考：rag\nlp\__init__.py + rag\app\book.py
  - title_frequency + sec_id 合并（论文/手册类）
      - 找到最常见标题级别 pivot，连续相同 sec_id 合并。
      - 参考：rag\app\paper.py, rag\app\manual.py

  5) 文档类型策略选择

  - manual
      - 如果 PDF 有可靠 outline（pdf_parser.outlines），优先用 outline level；否则 fallback 到 bullet + title_frequency。
      - 合并时考虑 token 预算（小段可以拼接）。
      - 参考：rag\app\manual.py
  - book
      - 有明显目录/章节模式，先 remove_contents_table，再 make_colon_as_title，hierarchical_merge(depth=5)。
      - 如果无明显 bullet 模式，回退到 naive_merge。
      - 参考：rag\app\book.py
  - laws
      - remove_contents_table + make_colon_as_title + tree_merge(depth=2)。
      - 参考：rag\app\laws.py
  - paper
      - 抽取标题/作者/摘要后，正文走 title_frequency 策略。
      - 抽象摘要为单独 chunk。
      - 参考：rag\app\paper.py

  6) 媒体上下文补齐

  - 表格/图片 chunk 常常只有结构或没有文本：
      - 在 chunk 前后按 token 预算取上下文句子拼到 context_above/context_below。
      - 参考：rag\nlp\__init__.py 的 attach_media_context
  - Ruby 复刻建议：
      - 先句子切分（按中英文标点），再按 token 预算截取。
      - 保留“上下文是补丁”的标记，避免后续重复归并。

  7) 位置与版面信息

  - RAGFlow 用 @@pn\tl\tr\tt\tb## 形式嵌入位置标签，再由 parser 解析出来。
      - 参考：rag\app\manual.py 内 tag() 与 pdf_parser.remove_tag/extract_positions
  - Ruby 复刻建议：
      - 保留位置数据结构（结构化字段），不要串入文本，便于后续裁剪/高亮。

  8) Tokenizer 与分块约束

  - 分块合并时使用 token 估算，而不是字符数。
  - naive_merge 支持“自定义分隔符”模式（反引号中是强分割）。
      - 参考：rag\nlp\__init__.py 的 naive_merge
  - Ruby 复刻：
      - 可接入 tiktoken Ruby 绑定或自定义 BPE tokenizer；至少要提供“近似 token 计数”能力。

  9) 关键接口建议

  - SmartChunking::Pipeline.chunk(document, parser_config, doc_type)
      - 输出 chunks[]，每个 chunk 带 text, doc_type, positions, image, context_above, context_below.
  - parser_config 推荐字段：
      - chunk_token_num, delimiter, table_context_size, image_context_size, layout_recognize.

  10) 伪代码（Ruby 版）

  sections, tables, images = Parser.parse(doc)
  sections = Cleaner.remove_contents(sections)
  sections = Cleaner.make_colon_as_title(sections)

  bull = StructureDetector.bullets_category(sections.map(&:text))

  chunks =
    case doc_type
    when :laws
      Merger.tree_merge(bull, sections, depth: 2)
    when :book
      bull >= 0 ? Merger.hierarchical_merge(bull, sections, depth: 5) :
                  Merger.naive_merge(sections, token_limit)
    when :paper, :manual
      pivot, levels = StructureDetector.title_frequency(bull, sections)
      Merger.merge_by_pivot(sections, levels, pivot, token_limit)
    else
      Merger.naive_merge(sections, token_limit)
    end

  chunks = Tokenizer.tokenize_chunks(chunks, doc_meta)
  chunks = MediaContext.attach(chunks, table_ctx, image_ctx)

  需要注意的差异/风险点

  - RAGFlow 在 PDF 上依赖 DeepDOC 的布局识别能力；Ruby 复刻时如果没有同级别布局解析，标题识别会明显下降。建议先做“layout-aware 解析”，再应用结构规则。
  - 处理中英文 bullet 规则时，要注意正则对 Unicode 的覆盖；RAGFlow 原始正则中包含中文数字、罗马数字等。
  - title_frequency 的 pivot 规则在非常短/混乱文档可能失效，务必提供 fallback（naive_merge）。

  如果你希望，我可以再给出一份“Ruby 代码骨架 + 正则集合 + 单元测试样例”，以便直接开工。你也可以告诉我你打算支持的文件类型范围，我会收敛方案。