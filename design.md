# SmartRAG 设计文档

## 1. 架构概述

SmartRAG 被设计为提供检索增强生成功能的模块化 Ruby gem。架构采用分层方法，关注点分离清晰。

系统采用混合检索架构，融合向量检索（语义理解）和全文检索（精确匹配）两种搜索方式，利用 RRF（Reciprocal Rank Fusion）算法优化搜索结果。

```
smart_rag/
├── lib/
│   ├── smart_rag/
│   │   ├── core/              # 核心功能
│   │   │   ├── embedding.rb          # 向量嵌入管理
│   │   │   ├── query_processor.rb    # 查询处理器（支持混合检索）
│   │   │   └── document_processor.rb # 文档处理器
│   │   ├── models/            # 数据库模型
│   │   │   ├── embedding.rb
│   │   │   ├── source_document.rb    # 源文档模型
│   │   │   ├── source_section.rb     # 文档片段模型
│   │   │   ├── tag.rb                # 标签模型
│   │   │   ├── section_fts.rb        # 全文检索专用表模型
│   │   │   └── text_search_config.rb # 语言配置模型
│   │   ├── services/          # 服务层
│   │   │   ├── embedding_service.rb       # 嵌入生成服务
│   │   │   ├── vector_search_service.rb   # 向量检索服务
│   │   │   ├── fulltext_search_service.rb # 全文检索服务
│   │   │   ├── hybrid_search_service.rb   # 混合检索服务
│   │   │   ├── tag_service.rb             # 标签生成服务
│   │   │   └── summarization_service.rb   # 摘要生成服务
│   │   ├── chunker/           # 文档分块
│   │   │   └── markdown_chunker.rb
│   │   ├── parsers/           # 查询解析器
│   │   │   └── query_parser.rb # 查询解析（语言检测、tsquery 构建）
│   │   └── config.rb
│   └── smart_rag.rb           # 主入口
├── db/
│   ├── migrations/            # 数据库迁移
│   ├── schema.sql
│   └── seeds/                 # 初始化数据
│       └── text_search_configs.sql
└── config/
    ├── smart_rag.yml          # 主配置
    └── fulltext_search.yml    # 全文检索配置
```

## 2. 核心组件

### 2.1 嵌入管理 (`core/embedding.rb`)

**职责：**
- 存储和检索向量嵌入
- 执行相似度搜索
- 管理基于标签的结果增强

**关键方法：**
```ruby
class SmartRAG::Core::Embedding
  def initialize(db_connection)
    # 使用数据库连接初始化
  end

  # 为源内容存储嵌入
  def store_embedding(source_id, vector)
    # 实现
  end

  # 按向量相似度搜索
  def search_by_vector(query_vector, limit = 5)
    # 使用 PostgreSQL <-> 操作符计算余弦距离
  end

  # 带标签增强的搜索
  def search_by_vector_with_tags(query_vector, tags, limit = 5)
    # 增强搜索，基于标签的评分
  end
end
```

**实现细节：**
- 使用 PostgreSQL 与 pgvector 扩展
- 将向量存储为 `vector` 类型列
- 与 source_sections 和 source_documents 连接以获取完整结果
- 为标签匹配实现加权评分

### 2.2 查询处理器 (`core/query_processor.rb`)

**职责：**
- 将自然语言转换为向量表示
- 生成搜索关键词/标签
- 格式化和排序搜索结果
- 生成自然语言响应

**关键方法：**
```ruby
class SmartRAG::Core::QueryProcessor
  def initialize(embedding_client, tag_generator, summarizer)
    @embedding_client = embedding_client
    @tag_generator = tag_generator
    @summarizer = summarizer
  end

  # 处理自然语言查询
  def process_query(query_text, language = :zh_cn, limit = 5)
    # 1. 从查询生成标签
    # 2. 将查询转换为向量
    # 3. 执行向量搜索
    # 4. 排序和格式化结果
  end

  # 生成自然语言响应
  def generate_response(question, search_results)
    # 使用摘要器创建自然答案
  end
end
```

**多语言支持：**
- 支持中文（简体/繁体）、英语、日语
- 为每种语言独立生成标签
- 通过 LLM 生成分类标签和内容标签

### 2.3 文档处理器 (`core/document_processor.rb`)

**职责：**
- 下载和处理文档
- 将各种格式转换为 Markdown
- 智能分块文档
- 管理文档生命周期

**关键方法：**
```ruby
class SmartRAG::Core::DocumentProcessor
  def process_url(url, options = {})
    # 1. 下载内容
    # 2. 提取元数据
    # 3. 转换为 Markdown
    # 4. 分块内容
    # 5. 生成嵌入
    # 6. 生成标签
  end
end
```

### 2.4 全文检索管理 (`core/fulltext_manager.rb`)

**职责：**
- 管理全文检索功能和 tsvector 索引
- 执行关键词搜索和查询解析
- 支持多语言分词和语言检测

**关键方法：**
```ruby
class SmartRAG::Core::FulltextManager
  def initialize(db_connection)
    @db = db_connection
  end

  # 存储或更新全文索引
  def update_fulltext_index(section_id, title, content, language = 'en')
    # 1. 检测语言
    # 2. 获取分词器配置
    # 3. 生成 tsvector
    # 4. 存储到 section_fts 表
  end

  # 基础全文检索
  def search_by_text(query, language = nil, limit = 20)
    # 1. 检测查询语言
    # 2. 构建 tsquery
    # 3. 执行数据库查询
    # 4. 返回排序结果
  end

  # 混合检索（与向量检索结合）
  def hybrid_search(text_query, vector_query, options = {})
    # 1. 并行执行全文检索和向量检索
    # 2. 使用 RRF 算法融合结果
    # 3. 返回最终排序结果
  end

  # 语言检测
  def detect_language(text)
    # 检查字符分布
    # 返回语言代码（en/zh/ja 等）
  end

  # 构建 tsquery
  def build_tsquery(text, language = 'en')
    # 支持自然语言查询解析
    # 支持高级查询语法（引号、AND、OR）
  end
end
```

**多语言支持实现：**
- 语言检测：基于字符范围的正则表达式检测
- 配置映射：从 `text_search_configs` 表获取分词器配置
- 中文分词：使用 pg_jieba 扩展，支持自定义词典
- 动态配置：根据文档元数据自动选择分词器

## 3. 数据模型

### 3.1 嵌入模型 (`models/embedding_model.rb`)

```sql
CREATE TABLE embeddings (
  id SERIAL PRIMARY KEY,
  source_id INTEGER NOT NULL REFERENCES source_sections(id),
  vector VECTOR(1024) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_embedding_vector ON embeddings USING ivfflat (vector vector_cosine_ops);
```

### 3.2 源文档模型 (`models/source_document.rb`)

```sql
CREATE TABLE source_documents (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  url TEXT,
  author VARCHAR(255),
  publication_date DATE,
  language VARCHAR(10),
  description TEXT,
  download_state SMALLINT DEFAULT 0, -- 0: 待处理, 1: 已完成, 2: 失败
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 3.3 源片段模型 (`models/source_section.rb`)

```sql
CREATE TABLE source_sections (
  id SERIAL PRIMARY KEY,
  document_id INTEGER NOT NULL REFERENCES source_documents(id),
  content TEXT NOT NULL,
  section_title VARCHAR(500),
  section_number INTEGER,
  tag_id INTEGER REFERENCES tags(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 3.4 相关表

```sql
-- 层级标签系统
CREATE TABLE tags (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  parent_id INTEGER REFERENCES tags(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 研究主题分类
CREATE TABLE research_topics (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 多对多关系
CREATE TABLE section_tags (
  section_id INTEGER REFERENCES source_sections(id),
  tag_id INTEGER REFERENCES tags(id),
  PRIMARY KEY (section_id, tag_id)
);

CREATE TABLE research_topic_sections (
  research_topic_id INTEGER REFERENCES research_topics(id),
  section_id INTEGER REFERENCES source_sections(id),
  PRIMARY KEY (research_topic_id, section_id)
);

CREATE TABLE research_topic_tags (
  research_topic_id INTEGER REFERENCES research_topics(id),
  tag_id INTEGER REFERENCES tags(id),
  PRIMARY KEY (research_topic_id, tag_id)
);
```

### 3.5 全文检索数据模型

#### 3.5.1 语言配置表 (`models/text_search_config.rb`)

```sql
-- 语言配置映射表
CREATE TABLE text_search_configs (
    language_code TEXT PRIMARY KEY,  -- 'en', 'zh', 'ja', etc.
    config_name TEXT NOT NULL,        -- 'pg_catalog.english', 'jieba', etc.
    is_installed BOOLEAN DEFAULT true
);

-- 初始化数据
INSERT INTO text_search_configs VALUES
    ('en', 'pg_catalog.english'),
    ('zh', 'jieba'),
    ('ja', 'pg_catalog.simple'),
    ('ko', 'pg_catalog.simple'),
    ('default', 'pg_catalog.simple');
```

#### 3.5.2 全文检索专用表 (`models/section_fts.rb`)

```sql
-- 全文检索专用表（方案 B：独立表设计）
CREATE TABLE section_fts (
    section_id INTEGER PRIMARY KEY REFERENCES source_sections(id) ON DELETE CASCADE,
    language TEXT NOT NULL,
    fts_title tsvector,  -- 标题字段（更高权重 A）
    fts_content tsvector,  -- 内容字段（权重 B）
    fts_combined tsvector,  -- 合并字段（标题+内容）
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建 GIN 索引以提高查询性能
CREATE INDEX section_fts_gin_idx ON section_fts USING GIN (fts_combined);
CREATE INDEX section_fts_language_idx ON section_fts (language);
CREATE INDEX section_fts_title_idx ON section_fts USING GIN (fts_title);

-- 分区索引（按语言）
CREATE INDEX section_fts_gin_zh ON section_fts USING GIN (fts_combined) WHERE language = 'zh';
CREATE INDEX section_fts_gin_en ON section_fts USING GIN (fts_combined) WHERE language = 'en';

-- 数据库触发器自动维护全文索引
CREATE OR REPLACE FUNCTION update_section_fts()
RETURNS TRIGGER AS $$
DECLARE
    v_language TEXT;
    v_config TEXT;
BEGIN
    -- 获取文档语言
    SELECT COALESCE(sd.language, 'en') INTO v_language
    FROM source_documents sd
    WHERE sd.id = NEW.document_id;

    -- 获取对应的配置
    SELECT COALESCE(tsc.config_name, 'pg_catalog.simple') INTO v_config
    FROM text_search_configs tsc
    WHERE tsc.language_code = v_language;

    -- 维护全文检索数据
    INSERT INTO section_fts (section_id, language, fts_title, fts_content, fts_combined)
    VALUES (
        NEW.id,
        v_language,
        setweight(to_tsvector(v_config, coalesce(NEW.section_title,'')), 'A'),
        setweight(to_tsvector(v_config, coalesce(NEW.content,'')), 'B'),
        setweight(to_tsvector(v_config, coalesce(NEW.section_title,'')), 'A') ||
        setweight(to_tsvector(v_config, coalesce(NEW.content,'')), 'B')
    )
    ON CONFLICT (section_id) DO UPDATE SET
        language = v_language,
        fts_title = setweight(to_tsvector(v_config, coalesce(NEW.section_title,'')), 'A'),
        fts_content = setweight(to_tsvector(v_config, coalesce(NEW.content,'')), 'B'),
        fts_combined = setweight(to_tsvector(v_config, coalesce(NEW.section_title,'')), 'A') ||
                      setweight(to_tsvector(v_config, coalesce(NEW.content,'')), 'B'),
        updated_at = CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trigger_update_section_fts
    AFTER INSERT OR UPDATE ON source_sections
    FOR EACH ROW EXECUTE FUNCTION update_section_fts();
```

#### 3.5.3 查询日志表（用于监控和优化）

```sql
-- 搜索查询性能监控表
CREATE TABLE search_logs (
    id SERIAL PRIMARY KEY,
    query TEXT NOT NULL,
    search_type VARCHAR(20), -- 'vector', 'fulltext', 'hybrid'
    execution_time_ms INTEGER,
    results_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX search_logs_created_at_idx ON search_logs (created_at);
CREATE INDEX search_logs_query_idx ON search_logs USING gin (to_tsvector('simple', query));
```

## 4. 文档分块系统

### 4.1 MarkdownChunker (`chunker/markdown_chunker.rb`)

**分块策略：**
1. 首先，按 Markdown 标题（#、##、###、####）拆分
2. 如果分块超过 max_chars，进一步按字符限制拆分
3. 保持分块之间的重叠以保留上下文

**算法：**
```ruby
class SmartRAG::Chunker::MarkdownChunker
  MAX_CHARS = 4000
  OVERLAP = 100

  def chunk(content)
    chunks = split_by_headers(content)
    chunks.flat_map { |chunk| enforce_size_limit(chunk) }
  end

  private

  def split_by_headers(content)
    # 使用正则表达式查找标题并相应拆分
  end

  def enforce_size_limit(chunk)
    if chunk.length <= MAX_CHARS
      [chunk]
    else
      # 带重叠拆分
    end
  end
end
```

**标题解析：**
- 使用正则表达式模式：`/^(#{headers.join("|")})\s+.+$/m`
- 保留标题层级
- 维护章节关系

## 5. 服务层

### 5.1 嵌入服务 (`services/embedding_service.rb`)

**用途：** 与外部嵌入 API 接口

```ruby
class SmartRAG::Services::EmbeddingService
  def initialize(provider_config)
    @provider = provider_config[:provider]
    @api_key = provider_config[:api_key]
    @endpoint = provider_config[:endpoint]
  end

  def generate_embedding(text, dimensions = 1024)
    # 调用外部嵌入 API
    # 返回向量数组
  end

  private

  def call_embedding_api(text)
    # HTTP 请求到嵌入服务
  end
end
```

### 5.2 向量搜索服务 (`services/vector_search_service.rb`)

**用途：** 执行向量相似度搜索

```ruby
class SmartRAG::Services::VectorSearchService
  def initialize(embedding_model)
    @embedding_model = embedding_model
  end

  def search(query, options = {})
    # 1. 生成查询向量（调用外部嵌入服务或缓存）
    # 2. 执行向量相似度搜索
    # 3. 返回排序结果
  end

  def search_by_vector(vector, options = {})
    # 直接使用预计算向量搜索
  end
end
```

### 5.3 全文检索服务 (`services/fulltext_search_service.rb`)

**用途：** 执行全文关键词搜索，支持多语言

```ruby
class SmartRAG::Services::FulltextSearchService
  def initialize(fulltext_manager, query_parser)
    @fulltext_manager = fulltext_manager
    @query_parser = query_parser
  end

  def search(query, options = {})
    # 1. 检测查询语言（自动或基于选项）
    # 2. 构建 tsquery
    # 3. 执行数据库查询
    # 4. 返回排序结果（含 BM25 分数、高亮片段）
  end

  def search_with_filters(query, filters, options = {})
    # 带过滤条件的全文检索
    # 支持按文档 ID、标签、日期范围过滤
  end
end
```

### 5.4 混合检索服务 (`services/hybrid_search_service.rb`)

**用途：** 融合全文检索和向量检索结果，提供最优搜索体验

```ruby
class SmartRAG::Services::HybridSearchService
  def initialize(vector_search_service, fulltext_search_service)
    @vector_search_service = vector_search_service
    @fulltext_search_service = fulltext_search_service
  end

  def search(query, options = {})
    # 1. 构建全文和向量查询
    # 2. 并行执行两种检索（使用线程池）
    # 3. 使用 RRF 算法融合结果
    # 4. 返回最终排序结果
  end

  private

  # RRF（Reciprocal Rank Fusion）算法实现
  def combine_results(fts_results, vector_results, k: 60)
    scores = {}

    # 全文检索得分
    fts_results.each_with_index do |result, index|
      rank = index + 1
      scores[result[:id]] = { fts_score: 1.0 / (k + rank), vector_score: 0, data: result }
    end

    # 向量检索得分
    vector_results.each_with_index do |result, index|
      rank = index + 1
      if scores[result[:id]]
        scores[result[:id]][:vector_score] = 1.0 / (k + rank)
      else
        scores[result[:id]] = { fts_score: 0, vector_score: 1.0 / (k + rank), data: result }
      end
    end

    # 排序并返回（按总分降序）
    scores.values.sort_by { |s| -(s[:fts_score] + s[:vector_score]) }.map { |s| s[:data] }
  end
end
```

**混合检索优势：**
- 结合全文检索的精确匹配和向量检索的语义理解
- 相比单一检索模式，召回率提升 15-25%
- 并行执行两种检索，性能开销最小化
- 支持配置权重，适应不同场景需求

### 5.3 标签服务 (`services/tag_service.rb`)

**用途：** 生成和管理标签

```ruby
class SmartRAG::Services::TagService
  def initialize(llm_client)
    @llm_client = llm_client
  end

  def generate_tags(text, topic, languages = [:zh_cn, :en])
    # 通过 LLM 生成分类标签和内容标签
    # 返回结构化标签数据
  end

  def find_or_create_tags(tag_names)
    # 确保标签存在于数据库
  end
end
```

### 5.4 摘要服务 (`services/summarization_service.rb`)

**用途：** 生成自然语言摘要

```ruby
class SmartRAG::Services::SummarizationService
  def initialize(llm_client)
    @llm_client = llm_client
  end

  def summarize_search_results(question, results)
    # 基于搜索结果生成连贯答案
  end
end
```

### 5.5 查询解析器 (`parsers/query_parser.rb`)

**用途：** 解析用户查询，检测语言并构建 tsquery

```ruby
class SmartRAG::Parsers::QueryParser
  def detect_language(text)
    # 基于字符范围的简单语言检测
    # 返回语言代码：en/zh/ja/ko
  end

  def build_tsquery(text, language = 'en')
    # 查询预处理：转义特殊字符、标准化
    # 判断查询类型（自然语言 / 高级语法）
    # 调用合适的转换函数：
    #   - plainto_tsquery: 自然语言查询
    #   - websearch_to_tsquery: 高级查询（引号、AND、OR）
    #   - phraseto_tsquery: 短语查询
  end

  def parse_advanced_query(text)
    # 解析引号、布尔操作符
    # 构建复杂的 tsquery 表达式
  end
end
```

## 6. 错误处理和日志记录

### 6.1 错误层级

```ruby
module SmartRAG
  module Errors
    class BaseError < StandardError; end

    class EmbeddingGenerationError < BaseError; end
    class VectorSearchError < BaseError; end
    class FulltextSearchError < BaseError; end
    class HybridSearchError < BaseError; end
    class DocumentProcessingError < BaseError; end
    class TagGenerationError < BaseError; end
    class DatabaseError < BaseError; end
    class LanguageDetectionError < BaseError; end
    class QueryParseError < BaseError; end
  end
end
```

### 6.2 日志系统

```ruby
module SmartRAG
  class Logger
    LEVELS = %i[debug info warn error fatal]

    def initialize(log_level = :info)
      @log_level = log_level
    end

    def log(level, message, context = {})
      return unless LEVELS.index(level) >= LEVELS.index(@log_level)

      # 结构化日志
      entry = {
        timestamp: Time.now.iso8601,
        level: level,
        message: message,
        context: context
      }

      puts entry.to_json
    end
  end
end
```

**日志类别：**
- 嵌入操作
- 搜索查询和结果
- 文档处理步骤
- 标签生成
- 数据库操作

## 7. 配置管理

### 7.1 配置结构 (`config/smart_rag.yml`)

```yaml
# 数据库配置
database:
  adapter: postgresql
  host: localhost
  port: 5432
  database: smart_rag_development
  username: username
  password: password
  pool: 5

# 嵌入配置
embedding:
  provider: openai  # 或其他提供商
  api_key: <%= ENV['EMBEDDING_API_KEY'] %>
  endpoint: https://api.openai.com/v1/embeddings
  model: text-embedding-ada-002
  dimensions: 1024

# 全文检索配置
fulltext_search:
  default_language: en  # 默认语言
  max_results: 100      # 最大结果数
  enable_jieba: true    # 启用中文分词
  custom_dict_path: null # 自定义词典路径

  # 混合检索权重配置
  hybrid_weight:
    fulltext: 0.4  # 全文检索权重
    vector: 0.6    # 向量检索权重

  # RRF 算法参数
  rrf_k: 60  # RRF 算法的 k 参数（通常 50-100）

  # 缓存配置
  cache:
    enabled: true
    ttl: 3600  # 缓存 TTL（秒）

  # 监控配置
  monitoring:
    log_slow_queries: true
    slow_query_threshold_ms: 100  # 慢查询阈值

  # 索引配置
  index:
    enable_partition: true  # 启用分区索引
    auto_vacuum: true       # 自动清理

# 分块配置
chunking:
  max_chars: 4000
  overlap: 100
  split_by_headers: true

# 搜索配置
search:
  default_limit: 5
  tag_boost_weight: 0.5  # 标签匹配的距离减少因子

# 标签/摘要生成的 LLM 配置
llm:
  provider: openai
  api_key: <%= ENV['LLM_API_KEY'] %>
  endpoint: https://api.openai.com/v1/chat/completions
  model: gpt-4
```

### 7.2 配置加载

```ruby
module SmartRAG
  class Config
    def self.load(file_path = nil)
      file_path ||= File.join(__dir__, '..', 'config', 'smart_rag.yml')
      yaml_content = File.read(file_path)
      YAML.safe_load(ERB.new(yaml_content).result, permitted_classes: [Symbol])
    end
  end
end
```

## 8. 主入口点

### 8.1 SmartRAG 模块

```ruby
require 'smart_rag/version'
require 'smart_rag/config'
require 'smart_rag/core/embedding'
require 'smart_rag/core/fulltext_manager'
require 'smart_rag/core/query_processor'
require 'smart_rag/core/document_processor'
require 'smart_rag/parsers/query_parser'
require 'smart_rag/models/*'
require 'smart_rag/services/*'
require 'smart_rag/chunker/markdown_chunker'

module SmartRAG
  class << self
    attr_accessor :config, :db, :logger

    def configure
      yield(config) if block_given?
    end

    def init_db
      @db = Sequel.connect(config[:database])
      load_models
    end

    def embedding_manager
      @embedding_manager ||= Core::Embedding.new(db)
    end

    def fulltext_manager
      @fulltext_manager ||= Core::FulltextManager.new(db)
    end

    def query_parser
      @query_parser ||= Parsers::QueryParser.new
    end

    def vector_search_service
      @vector_search_service ||= Services::VectorSearchService.new(embedding_manager)
    end

    def fulltext_search_service
      @fulltext_search_service ||= Services::FulltextSearchService.new(fulltext_manager, query_parser)
    end

    def hybrid_search_service
      @hybrid_search_service ||= Services::HybridSearchService.new(vector_search_service, fulltext_search_service)
    end

    def document_processor
      @document_processor ||= Core::DocumentProcessor.new(
        embedding_service,
        tag_service,
        chunker
      )
    end

    private

    def load_models
      Dir[File.join(__dir__, 'smart_rag', 'models', '*.rb')].each { |f| require f }
    end
  end
end
```

## 9. 使用示例

### 9.1 基础设置

```ruby
require 'smart_rag'

SmartRAG.config = SmartRAG::Config.load
SmartRAG.init_db
SmartRAG.logger = SmartRAG::Logger.new(:debug)

# 初始化服务
embedding_service = SmartRAG::Services::EmbeddingService.new(
  provider: :openai,
  api_key: ENV['OPENAI_API_KEY']
)
```

### 9.2 文档处理

```ruby
processor = SmartRAG.document_processor

# 处理网页文档
doc = processor.process_url(
  'https://example.com/article',
  topic_ids: [1, 2],
  generate_embeddings: true,
  generate_tags: true
)

puts "Document ID: #{doc.id}"
puts "Sections created: #{doc.sections.count}"
```

### 9.3 向量搜索

```ruby
# 简单向量搜索
results = SmartRAG.embedding_manager.search_by_vector(query_vector, limit: 5)

# 带标签增强的搜索
tags = ['machine learning', 'neural networks']
results = SmartRAG.embedding_manager.search_by_vector_with_tags(
  query_vector,
  tags,
  limit: 10
)

results.each do |result|
  puts "#{result[:document_title]} - Distance: #{result[:distance]}"
end
```

### 9.4 自然语言查询

```ruby
query_processor = SmartRAG::QueryProcessor.new(
  embedding_service,
  tag_service,
  summarization_service
)

# 处理自然语言问题
results = query_processor.process_query(
  "What are the latest developments in AI?",
  language: :en,
  limit: 5
)

# 生成自然语言答案
response = query_processor.generate_response(
  "What are the latest developments in AI?",
  results
)

puts response
```

## 10. 测试策略

### 10.1 测试结构

```
test/
├── fixtures/
│   ├── sample_documents/
│   └── sample_embeddings/
├── models/
│   ├── embedding_model_test.rb
│   ├── source_document_test.rb
│   └── source_section_test.rb
├── integration/
│   ├── document_processing_test.rb
│   └── search_flow_test.rb
├── chunker/
│   └── markdown_chunker_test.rb
└── test_helper.rb
```

### 10.2 关键测试场景

1. **向量搜索准确性**
   - 测试余弦距离计算
   - 验证标签增强逻辑
   - 基准搜索性能

2. **文档分块**
   - 测试 Markdown 标题拆分
   - 验证重叠处理
   - 测试边缘情况（无标题、超长章节）

3. **标签生成**
   - 模拟 LLM 响应
   - 验证标签链接逻辑
   - 测试多语言支持

4. **集成测试**
   - 端到端文档处理
   - 完整搜索流程
   - 错误恢复场景

## 11. 性能考虑

### 11.1 数据库优化

- **索引：**
  - 标签数组上的 GIN 索引以实现高效筛选
  - 向量列上的 IVFFLAT 索引以进行近似最近邻搜索
  - 外键和频繁查询列上的 B-tree 索引

- **查询优化：**
  - 使用 `SELECT ... LIMIT` 进行分页
  - 批量插入操作
  - 使用连接池（Sequel 的连接池）

### 11.2 缓存策略

```ruby
class SmartRAG::Cache
  def initialize(redis_client = nil)
    @redis = redis_client
    @memory_cache = {}
  end

  def fetch_embedding(key, &block)
    # 首先检查内存缓存
    # 然后检查 Redis（如果可用）
    # 最后计算并缓存
  end
end
```

### 11.3 后台处理

对于大型文档处理，考虑后台作业集成：

```ruby
# 未来增强
class DocumentProcessingJob
  def perform(url, options = {})
    SmartRAG.document_processor.process_url(url, options)
  end
end
```

## 12. 未来增强

### 12.1 高级功能

1. **混合搜索**
   - 结合向量搜索与全文搜索
   - 语义和关键词相关性之间的加权评分

2. **相关度反馈**
   - 从用户交互中学习
   - 基于反馈调整嵌入

3. **多模态嵌入**
   - 支持图像嵌入
   - 音频/视频内容索引

4. **语义聚类**
   - 自动分类文档
   - 主题建模集成

5. **查询扩展**
   - 自动用相关术语扩展查询
   - 使用 LLM 理解查询

### 12.2 可扩展性改进

1. **分布式搜索**
   - 跨多个数据库分片嵌入
   - 跨分片的联合搜索

2. **流式更新**
   - 实时嵌入更新
   - 增量索引

3. **存档系统**
   - 将旧嵌入移至冷存储
   - 可配置的保留策略

## 13. 安全考虑

1. **API 密钥管理**
   - 对凭证使用环境变量
   - 支持密钥轮换
   - 审计日志

2. **输入验证**
   - 清理所有文本输入
   - 下载前验证 URL
   - 文档大小限制

3. **数据库安全**
   - 使用预处理语句（Sequel 已处理）
   - 远程数据库的连接加密
   - 对数据库用户应用最小权限原则
