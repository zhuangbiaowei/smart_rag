# SmartRAG API 文档

## 概述

SmartRAG 是一个功能强大的 Ruby gem，提供混合检索增强生成功能，支持向量搜索、全文搜索和混合搜索。

## 前置条件

```ruby
require 'smart_rag'

# 初始化配置
SmartRAG.config = SmartRAG::Config.load('config/smart_rag.yml')
SmartRAG.db = Sequel.connect(SmartRAG.config[:database])
SmartRAG.logger = Logger.new(STDOUT)
```

## 核心 API

### SmartRAG::SmartRAG

主入口类，提供统一 API 接口。

#### 初始化

```ruby
config = {
  database: {
    adapter: 'postgresql',
    host: 'localhost',
    database: 'smart_rag_dev',
    user: 'username',
    password: 'password'
  },
  llm: {
    provider: 'openai',
    api_key: ENV['OPENAI_API_KEY']
  }
}

smart_rag = SmartRAG::SmartRAG.new(config)
```

#### 文档管理

##### 添加文档

```ruby
# 从文件添加
result = smart_rag.add_document('/path/to/document.pdf', {
  title: 'My Document',
  generate_embeddings: true,
  generate_tags: true,
  tags: ['important', 'research']
})

# 从 URL 添加
result = smart_rag.add_document('https://example.com/article', {
  generate_embeddings: true
})

# 返回值
{
  document_id: 123,
  section_count: 5,
  status: 'success'
}
```

**参数：**
- `document_path` (String): 文件路径或 URL
- `options` (Hash):
  - `title` (String): 文档标题（可选，自动提取）
  - `tags` (Array<String>): 标签列表
  - `generate_embeddings` (Boolean): 是否生成嵌入（默认: true）
  - `generate_tags` (Boolean): 是否自动生成标签（默认: false）

##### 删除文档

```ruby
result = smart_rag.remove_document(123)

# 返回值
{
  success: true,
  deleted_sections: 5,
  deleted_embeddings: 5
}
```

##### 获取文档详情

```ruby
doc = smart_rag.get_document(123)

# 返回值
{
  id: 123,
  title: 'My Document',
  description: 'Document description',
  author: 'John Doe',
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
  section_count: 5,
  metadata: { ... }
}
```

##### 列出文档

```ruby
# 获取第1页，每页20条
results = smart_rag.list_documents(page: 1, per_page: 20)

# 搜索文档
results = smart_rag.list_documents(search: 'machine learning')

# 返回值
{
  documents: [
    { id: 1, title: 'Doc 1', ... },
    { id: 2, title: 'Doc 2', ... }
  ],
  total_count: 100,
  page: 1,
  per_page: 20,
  total_pages: 5
}
```

**参数：**
- `page` (Integer): 页码（默认: 1）
- `per_page` (Integer): 每页数量（默认: 20，最大: 100）
- `search` (String): 搜索关键词（可选）

#### 搜索功能

##### 混合搜索（默认）

```ruby
results = smart_rag.search('artificial intelligence applications', {
  search_type: 'hybrid',    # 可选: 'hybrid', 'vector', 'fulltext'
  limit: 10,                # 最大结果数
  alpha: 0.7,               # 向量搜索权重（0-1）
  include_content: true,    # 包含完整内容
  include_metadata: true,   # 包含元数据
  filters: {                # 过滤器
    document_ids: [1, 2, 3],
    tag_ids: [4, 5, 6]
  }
})

# 返回值
{
  query: 'artificial intelligence applications',
  results: [
    {
      section_id: 456,
      document_id: 123,
      section_title: 'AI Overview',
      content: '...',
      similarity: 0.89,
      combined_score: 0.85,
      search_type: 'hybrid',
      metadata: {
        document_title: 'AI Research Paper',
        author: 'Jane Smith'
      }
    }
  ],
  metadata: {
    total_count: 10,
    execution_time_ms: 185,
    language: 'en',
    alpha: 0.7,
    text_result_count: 8,
    vector_result_count: 7,
    multilingual: false
  }
}
```

**参数：**
- `query` (String): 搜索查询
- `options` (Hash):
  - `search_type` (String): 搜索类型 ('hybrid', 'vector', 'fulltext')
  - `limit` (Integer): 最大结果数（默认: 20）
  - `alpha` (Float): 向量搜索权重，0-1之间（默认: 0.7）
  - `include_content` (Boolean): 是否包含完整内容
  - `include_metadata` (Boolean): 是否包含元数据
  - `filters` (Hash): 过滤器选项
    - `document_ids` (Array<Integer>): 文档ID列表
    - `tag_ids` (Array<Integer>): 标签ID列表
    - `date_from` (Date): 开始日期
    - `date_to` (Date): 结束日期

##### 向量搜索

```ruby
results = smart_rag.vector_search('machine learning algorithms', {
  limit: 5,
  include_content: true
})
```

##### 全文搜索

```ruby
results = smart_rag.fulltext_search('natural language processing', {
  limit: 5,
  include_metadata: true
})
```

#### 研究主题管理

##### 创建主题

```ruby
result = smart_rag.create_topic('AI in Healthcare', 'Applications of AI in medical field', {
  tags: ['AI', 'healthcare', 'medicine'],
  document_ids: [1, 2, 3]
})

# 返回值
{
  topic_id: 456,
  title: 'AI in Healthcare',
  description: 'Applications of AI in medical field',
  tags: ['AI', 'healthcare', 'medicine'],
  document_ids: [1, 2, 3]
}
```

##### 获取主题详情

```ruby
topic = smart_rag.get_topic(456)

# 返回值
{
  id: 456,
  title: 'AI in Healthcare',
  description: 'Applications of AI in medical field',
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
  tags: ['AI', 'healthcare', 'medicine'],
  document_count: 5
}
```

##### 列出主题

```ruby
results = smart_rag.list_topics(
  page: 1,
  per_page: 10,
  search: 'AI'
)
```

##### 更新主题

```ruby
result = smart_rag.update_topic(456, {
  title: 'AI in Medicine',
  tags: ['AI', 'medicine', 'technology']
})
```

##### 删除主题

```ruby
result = smart_rag.delete_topic(456)

# 返回值
{
  success: true,
  topic_id: 456
}
```

##### 添加文档到主题

```ruby
result = smart_rag.add_document_to_topic(456, 123)

# 返回值
{
  success: true,
  added_sections: 5,
  topic_id: 456,
  document_id: 123
}
```

##### 从主题移除文档

```ruby
result = smart_rag.remove_document_from_topic(456, 123)

# 返回值
{
  success: true,
  deleted_sections: 5,
  topic_id: 456,
  document_id: 123
}
```

##### 获取主题推荐

```ruby
recommendations = smart_rag.get_topic_recommendations(456, {
  limit: 10
})

# 返回值
{
  topic_id: 456,
  recommendations: [
    {
      section_id: 789,
      section_title: 'Machine Learning in Surgery',
      document_id: 234,
      matching_tags: 3
    }
  ]
}
```

#### 标签管理

##### 生成标签

```ruby
tags = smart_rag.generate_tags('Machine learning algorithms for text classification', {
  max_tags: 5,
  context: 'AI research'
})

# 返回值
{
  content_tags: ['machine learning', 'text classification', 'algorithms'],
  category_tags: ['AI', 'NLP']
}
```

##### 列出标签

```ruby
results = smart_rag.list_tags(
  page: 1,
  per_page: 50
)

# 返回值
{
  tags: [
    {
      id: 1,
      name: 'AI',
      parent_id: nil,
      section_count: 25,
      created_at: '2024-01-01T00:00:00Z'
    }
  ],
  total_count: 100,
  page: 1,
  per_page: 50,
  total_pages: 2
}
```

#### 系统统计

```ruby
stats = smart_rag.statistics

# 返回值
{
  document_count: 150,
  section_count: 750,
  topic_count: 25,
  tag_count: 85,
  embedding_count: 750
}
```

#### 搜索日志

```ruby
logs = smart_rag.search_logs(
  limit: 100,
  search_type: 'hybrid'
)

# 返回值
[
  {
    id: 1,
    query: 'artificial intelligence',
    search_type: 'hybrid',
    results_count: 10,
    execution_time_ms: 185,
    created_at: '2024-01-01T00:00:00Z'
  }
]
```

## Core Classes

### SmartRAG::Core::Embedding

向量嵌入管理类。

```ruby
embedding = SmartRAG::Core::Embedding.new(db_connection)

# 存储嵌入
embedding.store_embedding(section_id, vector)

# 向量搜索
results = embedding.search_by_vector(query_vector, limit: 5)

# 带标签增强的搜索
results = embedding.search_by_vector_with_tags(
  query_vector,
  tags,
  limit: 10
)
```

### SmartRAG::Core::QueryProcessor

查询处理器，支持自然语言处理。

```ruby
processor = SmartRAG::Core::QueryProcessor.new(
  config,
  embedding_manager,
  fulltext_manager
)

# 处理查询
results = processor.process_query(
  'What is machine learning?',
  language: :en,
  limit: 5
)

# 生成响应
response = processor.generate_response(
  'What is machine learning?',
  results
)
```

### SmartRAG::Core::DocumentProcessor

文档处理器，支持多种格式。

```ruby
processor = SmartRAG::Core::DocumentProcessor.new(
  embedding_manager,
  config
)

# 处理文档
document = processor.process_document(
  '/path/to/document.pdf',
  generate_embeddings: true,
  generate_tags: true
)
```

### SmartRAG::Services::TagService

标签服务，支持标签生成和管理。

```ruby
tag_service = SmartRAG::Services::TagService.new(llm_config)

# 生成标签
tags = tag_service.generate_tags(
  text,
  topic: 'AI research',
  languages: [:en]
)
```

## 错误处理

所有 API 调用都可能抛出以下错误：

```ruby
begin
  result = smart_rag.search('query')
rescue SmartRAG::Errors::ArgumentError => e
  # 参数错误
rescue SmartRAG::Errors::DatabaseError => e
  # 数据库错误
rescue SmartRAG::Errors::EmbeddingGenerationError => e
  # 嵌入生成失败
rescue SmartRAG::Errors::QueryProcessingError => e
  # 查询处理失败
rescue SmartRAG::Errors::TagGenerationError => e
  # 标签生成失败
rescue SmartRAG::Errors::DocumentProcessingError => e
  # 文档处理失败
end
```

## 最佳实践

### 1. 批量操作

```ruby
# 批量添加文档
doc_paths.each do |path|
  smart_rag.add_document(path, generate_embeddings: true)
end

# 使用线程池加速
require 'concurrent'

pool = Concurrent::FixedThreadPool.new(5)
doc_paths.each do |path|
  pool.post do
    smart_rag.add_document(path, generate_embeddings: true)
  end
end
pool.shutdown
pool.wait_for_termination
```

### 2. 缓存嵌入

```ruby
# 使用 Redis 缓存嵌入
require 'redis'

redis = Redis.new

# 检查缓存
cached = redis.get("embedding:#{content_hash}")
if cached
  embedding = JSON.parse(cached)
else
  embedding = smart_rag.generate_embedding(content)
  redis.set("embedding:#{content_hash}", embedding.to_json, ex: 3600)
end
```

### 3. 错误重试

```ruby
require 'retriable'

Retriable.retriable(on: SmartRAG::Errors::EmbeddingGenerationError, tries: 3) do
  result = smart_rag.add_document(path, generate_embeddings: true)
end
```

### 4. 异步处理

```ruby
# 使用后台任务处理大型文档
class DocumentProcessingJob
  def perform(document_path, options = {})
    smart_rag = SmartRAG::SmartRAG.new(config)
    smart_rag.add_document(document_path, options)
  end
end

# 使用 Sidekiq 或其他队列系统
DocumentProcessingJob.perform_async('/path/to/large_document.pdf')
```

### 5. 监控和日志

```ruby
# 配置详细日志
SmartRAG.logger = Logger.new('smart_rag.log')
SmartRAG.logger.level = Logger::DEBUG

# 监控搜索性能
result = smart_rag.search('query')
puts "Found #{result[:results].length} results in #{result[:metadata][:execution_time_ms]}ms"
```

## 性能优化

### 1. 数据库连接池

```ruby
# 配置连接池
config = {
  database: {
    adapter: 'postgresql',
    host: 'localhost',
    database: 'smart_rag_dev',
    user: 'username',
    password: 'password',
    pool: 25  # 增加连接池大小
  }
}
```

### 2. 批量插入

```ruby
# 批量添加文档比逐个添加更高效
documents.each_slice(10) do |batch|
  batch.each do |doc|
    smart_rag.add_document(doc[:path], doc[:options])
  end
end
```

### 3. 索引优化

```sql
-- 确保所有索引已创建
CREATE INDEX CONCURRENTLY idx_document_created_at ON source_documents (created_at);
CREATE INDEX CONCURRENTLY idx_section_document_id ON source_sections (document_id);
CREATE INDEX CONCURRENTLY idx_embedding_source_id ON embeddings (source_id);
```

### 4. 调整 RRF 参数

```ruby
# 根据数据集大小调整 RRF k 参数
results = smart_rag.search('query', {
  alpha: 0.7,  # 向量搜索权重
  limit: 10
})
```

### 5. 使用缓存

```ruby
# 启用查询缓存
require 'smart_rag/cache'

cache = SmartRAG::Cache.new(redis_client)

# 缓存搜索结果
cached_results = cache.fetch("search:#{query_hash}") do
  smart_rag.search(query)
end
```

## 迁移指南

### 从 v0.1 升级到 v0.2

#### 破坏性变更

1. **API 变更**
   - `add_document` 现在返回 hash 而不是 document 对象
   - `search` 方法返回格式已更新

2. **配置变更**
   - `config/smart_rag.yml` 结构已更新
   - 移除了 `embedding_service` 配置块

#### 迁移步骤

1. 更新配置文件

```yaml
# config/smart_rag.yml (v0.2)
database:
  adapter: postgresql
  # ... 其他配置

llm:
  provider: openai
  api_key: <%= ENV['OPENAI_API_KEY'] %>
  # ... 其他配置
```

2. 更新 API 调用

```ruby
# 旧代码 (v0.1)
doc = smart_rag.add_document('/path/to/doc.pdf')
doc_id = doc.id

# 新代码 (v0.2)
result = smart_rag.add_document('/path/to/doc.pdf')
doc_id = result[:document_id]
```

3. 更新错误处理

```ruby
# 旧代码 (v0.1)
begin
  smart_rag.search('query')
rescue StandardError => e
  # 处理错误
end

# 新代码 (v0.2)
begin
  smart_rag.search('query')
rescue SmartRAG::Errors::QueryProcessingError => e
  # 处理查询错误
rescue SmartRAG::Errors::EmbeddingGenerationError => e
  # 处理嵌入错误
end
```

### 数据库迁移

```ruby
# 运行新的迁移
bundle exec rake db:migrate

# 如果已有 embeddings 表，需要更新
class UpdateEmbeddingsFormat < Sequel::Migration
  def up
    alter_table :embeddings do
      # 更新向量格式
      set_column_type :vector, 'vector(1024)'
    end
  end
end
```

## 环境变量

```bash
# LLM API 密钥
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."

# 数据库连接
export DATABASE_URL="postgresql://user:pass@localhost:5432/smart_rag"

# 可选配置
export SMARTRAG_LOG_LEVEL="debug"
export SMARTRAG_MAX_WORKERS="5"
```

## 完整示例

```ruby
require 'smart_rag'
require 'logger'

# 配置
config = {
  database: {
    adapter: 'postgresql',
    host: 'localhost',
    database: 'smart_rag_dev',
    user: 'username',
    password: 'password'
  },
  llm: {
    provider: 'openai',
    api_key: ENV['OPENAI_API_KEY'],
    model: 'gpt-4'
  }
}

# 初始化
smart_rag = SmartRAG::SmartRAG.new(config)
smart_rag.logger = Logger.new(STDOUT)

# 1. 添加文档
result = smart_rag.add_document('https://arxiv.org/abs/2301.00001', {
  generate_embeddings: true,
  generate_tags: true
})

puts "Added document #{result[:document_id]} with #{result[:section_count]} sections"

# 2. 创建研究主题
topic = smart_rag.create_topic('Machine Learning Advances', 'Latest developments in ML', {
  tags: ['machine learning', 'AI'],
  document_ids: [result[:document_id]]
})

# 3. 搜索
search_results = smart_rag.search('transformer architecture', {
  search_type: 'hybrid',
  limit: 5,
  include_content: true,
  include_metadata: true
})

puts "Found #{search_results[:results].length} results"

search_results[:results].each do |result|
  puts "\n#{result[:section_title]}"
  puts result[:content][0..200] + "..."
  puts "Score: #{result[:combined_score]}"
end

# 4. 获取统计信息
stats = smart_rag.statistics
puts "\nTotal documents: #{stats[:document_count]}"
puts "Total sections: #{stats[:section_count]}"

# 5. 生成标签
tags = smart_rag.generate_tags('Deep learning for computer vision')
puts "\nGenerated tags: #{tags[:content_tags].join(', ')}"
```

## 支持

如有问题或需要支持，请查阅：

1. 设计文档：`design.md`
2. 设置文档：`SETUP.md`
3. 测试示例：`spec/integration/api_end_to_end_workflow_spec.rb`

## 版本信息

当前版本：1.0.0

## 许可证

MIT License
