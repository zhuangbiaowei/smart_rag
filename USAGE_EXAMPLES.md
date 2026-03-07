# SmartRAG Usage Examples and Best Practices

This guide provides practical examples and best practices for using SmartRAG in your applications.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Document Management](#document-management)
3. [Search Operations](#search-operations)
4. [Research Topic Management](#research-topic-management)
5. [Tag Management](#tag-management)
6. [Advanced Usage Patterns](#advanced-usage-patterns)
7. [Performance Best Practices](#performance-best-practices)
8. [Error Handling](#error-handling)
9. [Common Patterns](#common-patterns)

## Quick Start

### Basic Setup

```ruby
require 'smart_rag'
require 'logger'

# Initialize configuration
config = {
  database: {
    adapter: 'postgresql',
    host: ENV['SMARTRAG_DB_HOST'] || 'localhost',
    database: ENV['SMARTRAG_DB_NAME'] || 'smart_rag_development',
    user: ENV['SMARTRAG_DB_USER'] || 'smart_rag_user',
    password: ENV['SMARTRAG_DB_PASSWORD']
  },
  llm: {
    provider: 'openai',
    api_key: ENV['OPENAI_API_KEY']
  }
}

# Create SmartRAG instance
smart_rag = SmartRAG::SmartRAG.new(config)
smart_rag.logger = Logger.new(STDOUT)
smart_rag.logger.level = Logger::INFO

# Test the connection
puts "✓ SmartRAG initialized successfully"
stats = smart_rag.statistics
puts "✓ Database connected: #{stats[:document_count]} documents"
```

### First Document Addition

```ruby
# Add your first document
result = smart_rag.add_document(
  'https://example.com/ai-article.pdf',
  title: 'Introduction to AI',
  generate_embeddings: true,
  generate_tags: true
)

puts "✓ Document added: ID #{result[:document_id]}"
puts "✓ Sections created: #{result[:section_count]}"
```

### First Search

```ruby
# Perform your first search
results = smart_rag.search(
  'machine learning algorithms',
  search_type: 'hybrid',
  limit: 5,
  include_content: true
)

puts "\nSearch Results:"
results[:results].each_with_index do |result, i|
  puts "#{i + 1}. #{result[:section_title]} (score: #{result[:combined_score].round(3)})"
  puts "   #{result[:content][0..150]}..."
end
```

## Document Management

### Adding Documents from Various Sources

```ruby
# From a local file
smart_rag.add_document(
  '/path/to/document.pdf',
  title: 'Research Paper 2024',
  generate_embeddings: true
)

# From a URL
smart_rag.add_document(
  'https://arxiv.org/abs/2301.00001',
  generate_embeddings: true,
  generate_tags: true,
  tags: ['research', 'AI']
)

# With custom metadata
smart_rag.add_document(
  '/path/to/report.docx',
  title: 'Q3 Financial Report',
  generate_embeddings: false,  # Skip embeddings for non-technical docs
  metadata: {
    department: 'Finance',
    year: 2024,
    confidential: true
  }
)
```

### Batch Document Processing

```ruby
# Process multiple documents efficiently
documents = [
  { path: '/docs/paper1.pdf', tags: ['AI'] },
  { path: '/docs/paper2.pdf', tags: ['ML'] },
  { path: '/docs/paper3.pdf', tags: ['NLP'] }
]

# Sequential processing
documents.each do |doc|
  begin
    result = smart_rag.add_document(
      doc[:path],
      generate_embeddings: true,
      tags: doc[:tags]
    )
    puts "✓ Processed: #{doc[:path]}"
  rescue => e
    puts "✗ Failed: #{doc[:path]} - #{e.message}"
  end
end

# Parallel processing for better performance
require 'concurrent'

pool = Concurrent::FixedThreadPool.new(5)
documents.each do |doc|
  pool.post do
    begin
      smart_rag.add_document(
        doc[:path],
        generate_embeddings: true,
        tags: doc[:tags]
      )
      puts "✓ Processed: #{doc[:path]}"
    rescue => e
      puts "✗ Failed: #{doc[:path]} - #{e.message}"
    end
  end
end

pool.shutdown
pool.wait_for_termination
```

### Document Management Operations

```ruby
# List documents with pagination
docs_page_1 = smart_rag.list_documents(page: 1, per_page: 20)
docs_page_2 = smart_rag.list_documents(page: 2, per_page: 20)

# Search for specific documents
ml_docs = smart_rag.list_documents(search: 'machine learning')

# Get document details
doc = smart_rag.get_document(123)
puts "Title: #{doc[:title]}"
puts "Sections: #{doc[:section_count]}"
puts "Created: #{doc[:created_at]}"

# Remove a document
result = smart_rag.remove_document(123)
puts "Deleted sections: #{result[:deleted_sections]}"
puts "Deleted embeddings: #{result[:deleted_embeddings]}"
```

## Search Operations

### Hybrid Search (Default)

Hybrid search combines vector and full-text search for optimal results.

```ruby
# Basic hybrid search
results = smart_rag.search(
  'deep learning applications in healthcare',
  search_type: 'hybrid',
  limit: 10,
  alpha: 0.7  # Weight for vector search (0.0 = pure text, 1.0 = pure vector)
)

# With content and metadata
results = smart_rag.search(
  'natural language processing',
  search_type: 'hybrid',
  limit: 5,
  include_content: true,
  include_metadata: true
)

# Search with filters
results = smart_rag.search(
  'artificial intelligence',
  search_type: 'hybrid',
  limit: 10,
  filters: {
    document_ids: [1, 2, 3],  # Search only in specific documents
    tag_ids: [4, 5]           # Filter by tags
  }
)
```

### Vector Search

Useful for semantic similarity searches.

```ruby
# Pure vector search
results = smart_rag.vector_search(
  'neural network architectures',
  limit: 5
)

# Vector search with tag boosting
results = smart_rag.vector_search(
  'transformer models',
  limit: 10,
  tag_boost_weight: 0.1  # Boost results with matching tags
)
```

### Full-Text Search

Best for exact keyword matching and boolean queries.

```ruby
# Basic full-text search
results = smart_rag.fulltext_search(
  'convolutional neural networks',
  limit: 5
)

# Advanced boolean query
results = smart_rag.fulltext_search(
  'artificial AND (intelligence OR learning) AND NOT robotics',
  limit: 10
)

# Phrase search
results = smart_rag.fulltext_search(
  '"deep reinforcement learning"',
  limit: 5
)
```

### Multi-language Search

SmartRAG automatically detects and handles multiple languages.

```ruby
# Chinese search
results = smart_rag.search('人工智能应用', language: 'zh_cn')

# Japanese search
results = smart_rag.search('機械学習アルゴリズム', language: 'ja')

# Korean search
results = smart_rag.search('딥러닝 모델', language: 'ko')

# Mixed language search (auto-detect)
results = smart_rag.search('AI和机器学习的发展', language: 'auto')
```

## Research Topic Management

### Creating and Organizing Topics

```ruby
# Create a research topic
topic = smart_rag.create_topic(
  'AI in Healthcare',
  'Applications of artificial intelligence in medical diagnosis and treatment',
  tags: ['AI', 'healthcare', 'medicine', 'diagnosis'],
  document_ids: [1, 2, 3]  # Associate existing documents
)

# Create nested topic structure
parent_topic = smart_rag.create_topic(
  'Machine Learning',
  'Fundamental ML concepts and algorithms'
)

child_topic = smart_rag.create_topic(
  'Deep Learning',
  'Neural network based learning',
  tags: ['neural_networks', 'deep_learning']
  # Could link to parent if hierarchical topics are supported
)
```

### Managing Topic Content

```ruby
# Add documents to a topic
topic_id = 456
document_id = 123

result = smart_rag.add_document_to_topic(topic_id, document_id)
puts "Added #{result[:added_sections]} sections to topic"

# Get topic recommendations
recommendations = smart_rag.get_topic_recommendations(topic_id, limit: 10)

recommendations[:recommendations].each do |rec|
  puts "Recommended: #{rec[:section_title]}"
  puts "  Matching tags: #{rec[:matching_tags]}"
  puts "  Score: #{rec[:relevance_score]}"
end

# List all topics
topics = smart_rag.list_topics(page: 1, per_page: 20)
topics[:topics].each do |topic|
  puts "#{topic[:title]} (#{topic[:document_count]} documents)"
end
```

## Tag Management

### Automatic Tag Generation

```ruby
# Generate tags for text
text = """
Machine learning is a subset of artificial intelligence that enables systems
to learn and improve from experience without being explicitly programmed.
It focuses on developing computer programs that can access data and use it
to learn for themselves.
"""

tags = smart_rag.generate_tags(text, topic: 'AI Introduction')
puts "Categories: #{tags[:categories].join(', ')}"
puts "Content tags: #{tags[:content_tags].join(', ')}"

# Batch generate tags for document sections
document = smart_rag.get_document(1)
sections = document[:sections]

tags_by_section = {}
sections.each do |section|
  tags = smart_rag.generate_tags(
    section[:content],
    topic: document[:title],
    max_tags: 5
  )
  tags_by_section[section[:id]] = tags
end
```

### Manual Tag Management

```ruby
# Create hierarchical tags
tag_service = SmartRAG::Services::TagService.new

hierarchy = {
  "Technology" => {
    "AI" => ["Machine Learning", "Deep Learning", "Neural Networks"],
    "Programming" => ["Python", "Ruby", "JavaScript"]
  }
}

created_tags = tag_service.create_hierarchy(hierarchy)

# Associate tags with content
tag = SmartRAG::Models::Tag.find_or_create("machine_learning")
section = SmartRAG::Models::SourceSection[1]

# Add tag to section
section.add_tag(tag)

# Find content by tag
ml_sections = tag.sections
ml_sections.each do |section|
  puts "#{section.section_title}: #{section.content[0..100]}..."
end

# Search for tags
tags = tag_service.search_tags('learn', limit: 10)
tags.each { |tag| puts "#{tag.name} (#{tag.section_count} sections)" }
```

## Advanced Usage Patterns

### Context-Aware Search

```ruby
class ContextualSearch
  def initialize(smart_rag)
    @smart_rag = smart_rag
    @search_history = []
  end

  def search_with_context(query, user_context = {})
    # Enhance query with context
    enhanced_query = enhance_query(query, user_context)

    # Perform search
    results = @smart_rag.search(
      enhanced_query,
      search_type: 'hybrid',
      limit: 10,
      filters: build_filters(user_context)
    )

    # Store in history
    @search_history << { query: query, context: user_context, results: results }

    results
  end

  private

  def enhance_query(query, context)
    # Add context-specific terms
    case context[:domain]
    when 'healthcare'
      "#{query} medical health clinical"
    when 'finance'
      "#{query} financial economic banking"
    else
      query
    end
  end

  def build_filters(context)
    filters = {}
    filters[:document_ids] = context[:document_ids] if context[:document_ids]
    filters[:tag_ids] = context[:preferred_tags] if context[:preferred_tags]
    filters
  end
end

# Usage
contextual_search = ContextualSearch.new(smart_rag)
results = contextual_search.search_with_context(
  'risk assessment',
  user_context: {
    domain: 'finance',
    document_ids: [1, 2, 3],
    preferred_tags: [4, 5]
  }
)
```

### Search Result Processing Pipeline

```ruby
class SearchPipeline
  def initialize(smart_rag)
    @smart_rag = smart_rag
    @processors = []
  end

  def add_processor(&block)
    @processors << block
    self
  end

  def search(query, options = {})
    # Initial search
    results = @smart_rag.search(query, options)

    # Process through pipeline
    @processors.each do |processor|
      results = processor.call(results, query, options)
    end

    results
  end
end

# Create pipeline with processors
pipeline = SearchPipeline.new(smart_rag)

# Add relevance scoring
pipeline.add_processor do |results, query, options|
  results[:results].each do |result|
    result[:relevance_score] = calculate_relevance(result, query)
  end
  results
end

# Add result filtering
pipeline.add_processor do |results, query, options|
  min_score = options[:min_score] || 0.5
  results[:results].select! { |r| r[:relevance_score] >= min_score }
  results[:metadata][:filtered_count] = results[:results].length
  results
end

# Use pipeline
results = pipeline.search(
  'neural networks',
  min_score: 0.7,
  limit: 20
)
```

### Caching Search Results

```ruby
require 'redis'

class CachedSmartRAG
  def initialize(smart_rag, redis_client)
    @smart_rag = smart_rag
    @redis = redis_client
    @cache_ttl = 3600  # 1 hour
  end

  def search(query, options = {})
    # Create cache key
    cache_key = create_cache_key(query, options)

    # Try to get from cache
    cached = @redis.get(cache_key)
    if cached
      puts "Cache hit for: #{query}"
      return JSON.parse(cached, symbolize_names: true)
    end

    # Perform search
    results = @smart_rag.search(query, options)

    # Store in cache
    @redis.setex(cache_key, @cache_ttl, results.to_json)

    puts "Cache miss for: #{query}"
    results
  end

  private

  def create_cache_key(query, options)
    key_parts = [query, options.sort].flatten.join(':')
    "search:#{Digest::MD5.hexdigest(key_parts)}"
  end
end

# Usage
redis = Redis.new
$cached_rag = CachedSmartRAG.new(smart_rag, redis)

# First search - cache miss
results1 = $cached_rag.search('deep learning', limit: 10)

# Second search - cache hit
results2 = $cached_rag.search('deep learning', limit: 10)
```

### Building a Q&A System

```ruby
class QA_system
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def answer(question, options = {})
    # Search for relevant information
    search_results = @smart_rag.search(
      question,
      search_type: 'hybrid',
      limit: options[:context_limit] || 5,
      include_content: true
    )

    # Generate answer based on search results (requires LLM integration)
    answer = generate_answer(question, search_results[:results])

    {
      question: question,
      answer: answer,
      sources: extract_sources(search_results[:results]),
      confidence: calculate_confidence(search_results[:results])
    }
  end

  private

  def generate_answer(question, results)
    return "I don't have enough information to answer this question." if results.empty?

    # Combine relevant content
    context = results.map { |r| r[:content] }.join("\n\n---\n\n")

    # Here you would call an LLM API to generate the answer
    # This is a simplified version
    "Based on the available information: #{context[0..500]}..."
  end

  def extract_sources(results)
    results.map do |result|
      {
        section_id: result[:section_id],
        title: result[:section_title],
        score: result[:combined_score]
      }
    end
  end

  def calculate_confidence(results)
    return 0.0 if results.empty?

    # Simple confidence based on top result score
    [results.first[:combined_score], 1.0].min
  end
end

# Usage
qa = QA_system.new(smart_rag)
response = qa.answer(
  'What are the applications of transformers in NLP?',
  context_limit: 3
)

puts "Answer: #{response[:answer]}"
puts "Confidence: #{(response[:confidence] * 100).round(1)}%"
puts "Sources:"
response[:sources].each do |source|
  puts "  - #{source[:title]} (ID: #{source[:section_id]})"
end
```

## Performance Best Practices

### 1. Batch Operations

```ruby
# Instead of individual operations
bad_practice = documents.map do |doc|
  smart_rag.add_document(doc[:path], generate_embeddings: true)
end

# Use batch processing
good_practice = documents.each_slice(10) do |batch|
  # Process batch in parallel
  batch.map do |doc|
    Concurrent::Promises.future do
      smart_rag.add_document(doc[:path], generate_embeddings: true)
    end
  end.map(&:value)
end
```

### 2. Connection Pooling

```ruby
# Configure database connection pool
config = {
  database: {
    adapter: 'postgresql',
    host: 'localhost',
    database: 'smart_rag',
    user: 'user',
    password: 'pass',
    pool: 25,              # Increase pool size
    timeout: 5000,         # Connection timeout
    max_connections: 100   # Maximum connections
  }
}
```

### 3. Efficient Searching

```ruby
# Use appropriate search types for queries
# For exact matches
text_results = smart_rag.fulltext_search('error code 404', limit: 5)

# For conceptual similarity
vector_results = smart_rag.vector_search('debugging techniques', limit: 5)

# For general queries
hybrid_results = smart_rag.search('how to fix bugs', search_type: 'hybrid')

# Adjust alpha based on use case
# - Technical/keyword-heavy: lower alpha (0.3-0.5)
# - Conceptual/exploratory: higher alpha (0.7-0.9)
```

### 4. Caching Strategies

```ruby
# Cache embeddings for repeated content
class EmbeddingCache
  def initialize
    @cache = {}
  end

  def get_embedding(text)
    hash = Digest::MD5.hexdigest(text)
    @cache[hash] ||= generate_embedding(text)
  end
end

# Cache search results
class SearchCache
  def initialize(redis, ttl: 3600)
    @redis = redis
    @ttl = ttl
  end

  def fetch(query, options = {}, &block)
    key = cache_key(query, options)

    if result = @redis.get(key)
      JSON.parse(result, symbolize_names: true)
    else
      result = block.call
      @redis.setex(key, @ttl, result.to_json)
      result
    end
  end
end
```

### 5. Database Optimization

```sql
-- Create optimized indexes
CREATE INDEX CONCURRENTLY idx_section_fts_content
  ON section_fts USING gin(to_tsvector('english', content));

CREATE INDEX CONCURRENTLY idx_embeddings_vector
  ON embeddings USING ivfflat (vector vector_cosine_ops)
  WITH (lists = 100);

-- Monitor and optimize slow queries
EXPLAIN ANALYZE
SELECT * FROM hybrid_search('machine learning', 10);
```

## Error Handling

### Comprehensive Error Handling

```ruby
begin
  result = smart_rag.add_document(
    '/path/to/document.pdf',
    generate_embeddings: true
  )
rescue SmartRAG::Errors::ArgumentError => e
  puts "Invalid arguments: #{e.message}"
rescue SmartRAG::Errors::DatabaseError => e
  puts "Database error: #{e.message}"
  # Attempt to reconnect or use fallback
rescue SmartRAG::Errors::EmbeddingGenerationError => e
  puts "Embedding generation failed: #{e.message}"
  # Retry or skip embeddings
rescue SmartRAG::Errors::DocumentProcessingError => e
  puts "Document processing failed: #{e.message}"
  # Log and continue with next document
rescue => e
  puts "Unexpected error: #{e.message}"
  # Log for investigation
end
```

### Retry Logic

```ruby
require 'retriable'

class RetryableSmartRAG
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def add_document(path, options = {})
    Retriable.retriable(
      on: [SmartRAG::Errors::EmbeddingGenerationError],
      tries: 3,
      base_interval: 1,
      multiplier: 2
    ) do
      @smart_rag.add_document(path, options)
    end
  end

  def search(query, options = {})
    Retriable.retriable(
      on: [SmartRAG::Errors::DatabaseError],
      tries: 3,
      base_interval: 0.5
    ) do
      @smart_rag.search(query, options)
    end
  end
end
```

## Common Patterns

### Pattern 1: Document Processing Pipeline

```ruby
class DocumentPipeline
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def process(files, options = {})
    results = []

    files.each do |file|
      begin
        # Step 1: Add document
        doc_result = @smart_rag.add_document(
          file,
          generate_embeddings: false  # Delay embedding generation
        )

        # Step 2: Generate tags
        tags = @smart_rag.generate_tags(
          extract_text(file),
          topic: options[:topic]
        )

        # Step 3: Apply tags
        if doc_result[:document_id]
          document = SmartRAG::Models::SourceDocument[doc_result[:document_id]]
          sections = document.sections

          sections.each do |section|
            tag_objects = tags[:content_tags].map do |tag_name|
              SmartRAG::Models::Tag.find_or_create(tag_name)
            end

            section.add_tag(*tag_objects)
          end

          # Step 4: Generate embeddings (batch)
          document.sections.each do |section|
            embedding = @smart_rag.generate_embedding(section.content)
            store_embedding(section.id, embedding)
          end
        end

        results << { success: true, file: file, document_id: doc_result[:document_id] }
      rescue => e
        results << { success: false, file: file, error: e.message }
      end
    end

    results
  end
end
```

### Pattern 2: Incremental Indexing

```ruby
class IncrementalIndexer
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def index_new_documents(source_dir, last_check = nil)
    # Find new or modified documents
    pattern = File.join(source_dir, '**/*.pdf')
    documents = Dir.glob(pattern)

    if last_check
      documents.select! { |doc| File.mtime(doc) > last_check }
    end

    # Process in batches
    documents.each_slice(10) do |batch|
      batch_results = process_batch(batch)
      log_results(batch_results)
    end
  end

  private

  def process_batch(files)
    files.map do |file|
      begin
        result = @smart_rag.add_document(file, generate_embeddings: true)
        { file: file, success: true, document_id: result[:document_id] }
      rescue => e
        { file: file, success: false, error: e.message }
      end
    end
  end
end
```

### Pattern 3: Search Analytics

```ruby
class SearchAnalytics
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def analyze_search_patterns(days = 30)
    logs = smart_rag.search_logs(limit: 1000)

    analytics = {
      total_searches: logs.length,
      avg_execution_time: logs.sum { |l| l[:execution_time_ms] } / logs.length,
      popular_queries: popular_queries(logs),
      failed_searches: logs.count { |l| l[:results_count] == 0 },
      trend_analysis: trend_analysis(logs, days)
    }
  end

  def identify_content_gaps(logs)
    no_result_queries = logs.select { |l| l[:results_count] == 0 }

    # Group similar queries
    clusters = cluster_queries(no_result_queries)

    # Identify topics needing more content
    clusters.map do |cluster|
      {
        topic: cluster[:topic],
        query_count: cluster[:queries].length,
        sample_queries: cluster[:queries].first(3)
      }
    end
  end
end
```

### Pattern 4: Multi-tenant Applications

```ruby
class MultiTenantSmartRAG
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def add_document(tenant_id, path, options = {})
    # Add tenant isolation
    options[:metadata] ||= {}
    options[:metadata][:tenant_id] = tenant_id

    @smart_rag.add_document(path, options)
  end

  def search(tenant_id, query, options = {})
    # Filter by tenant
    options[:filters] ||= {}
    options[:filters][:metadata] = { tenant_id: tenant_id }

    @smart_rag.search(query, options)
  end

  def get_statistics(tenant_id)
    # Get tenant-specific stats
    @smart_rag.statistics(tenant_id: tenant_id)
  end
end
```

## Summary

This guide has covered:

1. **Quick Start** - Basic setup and first operations
2. **Document Management** - Adding, organizing, and managing documents
3. **Search Operations** - Various search types and advanced filtering
4. **Research Topics** - Organizing content into thematic collections
5. **Tag Management** - Automatic and manual tagging strategies
6. **Advanced Patterns** - Production-ready implementations
7. **Performance** - Best practices for optimal performance
8. **Error Handling** - Robust error management strategies
9. **Common Patterns** - Reusable solutions for typical scenarios

For more information, see:
- [API Documentation](API_DOCUMENTATION.md) - Complete API reference
- [Performance Guide](PERFORMANCE_GUIDE.md) - Performance optimization details
- [Migration Guide](MIGRATION_GUIDE.md) - Version upgrade instructions

## Support

- GitHub Issues: https://github.com/your-org/smart_rag/issues
- Documentation Issues: Report any errors or inconsistencies in examples
- Community Forum: Share your usage patterns and learn from others
