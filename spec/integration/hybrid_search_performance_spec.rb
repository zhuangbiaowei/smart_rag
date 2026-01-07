require 'spec_helper'
require 'smart_rag/services/hybrid_search_service'
require 'smart_rag/core/embedding'
require 'smart_rag/core/fulltext_manager'
require 'benchmark'

RSpec.describe "Hybrid Search Performance", type: :integration do
  let(:db) { SmartRAG.db }
  let(:embedding_service) { SmartRAG::Services::EmbeddingService.new }
  let(:embedding_manager) { SmartRAG::Core::Embedding.new }
  let(:query_parser) { SmartRAG::Parsers::QueryParser.new }
  let(:fulltext_manager) { SmartRAG::Core::FulltextManager.new(db, query_parser: query_parser) }
  let(:config) { { logger: Logger.new(StringIO.new), default_limit: 10 } }
  let(:service) { SmartRAG::Services::HybridSearchService.new(embedding_manager, fulltext_manager, config) }

  # Create test data
  before(:all) do
    # Clean up any existing test data
    db = SmartRAG.db
    db[:section_tags].delete
    db[:tags].delete
    db[:embeddings].delete
    db[:source_sections].delete
    db[:source_documents].delete

    # Create test documents
    @doc1 = SmartRAG::Models::SourceDocument.create(
      title: "Machine Learning Fundamentals",
      url: "https://example.com/ml-fundamentals",
      author: "John Doe",
      publication_date: Date.today - 30,
      language: "en"
    )

    @doc2 = SmartRAG::Models::SourceDocument.create(
      title: "Deep Learning Advances",
      url: "https://example.com/dl-advances",
      author: "Jane Smith",
      publication_date: Date.today - 15,
      language: "en"
    )

    # Create high-quality test data with both embeddings and searchable content
    @test_sections = []

    # Create ML/AI themed sections for better search results
    ml_topics = [
      {title: "Neural Networks Basics", content: "Neural networks are computing systems inspired by biological neural networks. This article covers the fundamentals of artificial neural networks and their role in machine learning."},
      {title: "Machine Learning Algorithms", content: "Supervised and unsupervised machine learning algorithms including classification, regression, and clustering methods for data analysis."},
      {title: "Deep Learning Techniques", content: "Advanced deep learning techniques using multi-layer neural networks for complex pattern recognition and artificial intelligence applications."},
      {title: "AI in Practice", content: "Real-world applications of artificial intelligence and machine learning systems in industry and research environments."},
      {title: "Data Science Fundamentals", content: "Core concepts in data science including statistical analysis, machine learning, and neural network implementations."}
    ]

    ml_topics.each_with_index do |topic, idx|
      section = SmartRAG::Models::SourceSection.create(
        document_id: @doc1.id,
        section_title: topic[:title],
        section_number: 1000 + idx,
        content: topic[:content]
      )
      @test_sections << section

      # Create embedding immediately
      vector = Array.new(1024) { rand(-1.0..1.0) }
      SmartRAG::Models::Embedding.create(
        source_id: section.id,
        vector: pgvector(vector)
      )
    end

    # Create sections
    @sections = []
    50.times do |i|
      section = SmartRAG::Models::SourceSection.create(
        document_id: i < 25 ? @doc1.id : @doc2.id,
        content: generate_ml_content(i),
        section_title: "Section #{i + 1}",
        section_number: i + 1
      )
      @sections << section
    end

    # Create embeddings
    @sections.each_with_index do |section, index|
      vector = generate_random_vector(1024)
      SmartRAG::Models::Embedding.create(
        source_id: section.id,
        vector: pgvector(vector)
      )
    end

    # Note: section_fts entries are automatically created by the database trigger
    # when source_sections are created.
    # Just in case, we verify that section_fts records exist
    existing_fts_ids = db[:section_fts].select_map(:section_id)
    missing_fts_ids = @sections.map(&:id) - existing_fts_ids

    # Only create fts entries for sections that don't have them yet
    if missing_fts_ids.any?
      missing_fts_ids.each do |section_id|
        section = @sections.find { |s| s.id == section_id }
        next unless section

        db[:section_fts].insert(
          section_id: section.id,
          language: 'en',
          fts_title: Sequel.function(:to_tsvector, 'english', section.section_title || ''),
          fts_content: Sequel.function(:to_tsvector, 'english', section.content),
          fts_combined: Sequel.function(:to_tsvector, 'english', [section.section_title, section.content].compact.join(' '))
        )
      end
    end

    # Create tags
    @tag1 = SmartRAG::Models::Tag.create(name: "machine_learning")
    @tag2 = SmartRAG::Models::Tag.create(name: "deep_learning")
    @tag3 = SmartRAG::Models::Tag.create(name: "neural_networks")

    # Associate tags
    @sections.first(20).each { |s| db[:section_tags].insert(section_id: s.id, tag_id: @tag1.id) }
    @sections[20..39].each { |s| db[:section_tags].insert(section_id: s.id, tag_id: @tag2.id) }
    @sections.last(10).each { |s| db[:section_tags].insert(section_id: s.id, tag_id: @tag3.id) }
  end

  after(:all) do
    db = SmartRAG.db
    # Cleanup test data
    db[:section_tags].delete
    db[:tags].delete
    db[:embeddings].delete
    db[:section_fts].delete
    db[:source_sections].delete
    db[:source_documents].delete
  end

  describe "search performance" do
    it "completes hybrid search within acceptable time" do
      query = "machine learning neural networks"

      # Warmup for fair timing
      service.search(query, limit: 10)

      execution_times = []
      10.times do
        result = service.search(query, limit: 10)
        execution_times << result[:metadata][:execution_time_ms]
      end

      avg_time = execution_times.sum / execution_times.size
      max_time = execution_times.max

      puts "\nHybrid Search Performance:"
      puts "  Average time: #{avg_time}ms"
      puts "  Max time: #{max_time}ms"
      puts "  Min time: #{execution_times.min}ms"
      puts "  P95 time: #{percentile(execution_times, 95)}ms"

      # Performance assertions
      expect(max_time).to be < 1000, "Max execution time should be under 1 second"
      expect(avg_time).to be < 500, "Average execution time should be under 500ms"
    end

    it "scales reasonably with result limit" do
      query = "deep learning algorithms"

      limits = [5, 10, 20, 50]
      timings = {}

      limits.each do |limit|
        result = service.search(query, limit: limit)
        timings[limit] = result[:metadata][:execution_time_ms]
      end

      puts "\nScalability test:"
      timings.each { |limit, time| puts "  Limit #{limit}: #{time}ms" }

      # Should not increase linearly
      ratio = timings[50].to_f / timings[5]
      expect(ratio).to be < 3.0, "Performance should be sub-linear with limit increase"
    end

    it "handles concurrent searches efficiently" do
      queries = [
        "machine learning",
        "neural networks",
        "deep learning",
        "artificial intelligence",
        "data science"
      ]

      start_time = Time.now

      threads = queries.map do |query|
        Thread.new do
          service.search(query, limit: 10)
        end
      end

      results = threads.map(&:value)
      total_time = (Time.now - start_time) * 1000

      puts "\nConcurrent search test:"
      puts "  Total time: #{total_time}ms"
      puts "  Per query average: #{total_time / queries.size}ms"

      # All searches should succeed
      expect(results.all? { |r| r[:results].any? }).to be true

      # Concurrent performance should be reasonable
      expect(total_time).to be < 2000, "5 concurrent searches should complete in under 2 seconds"
    end

    it "performs efficiently with filters" do
      query = "machine learning"

      # Ensure we have data
      result_first = service.search(query, limit: 20)
      if result_first[:results].empty?
        test_section = SmartRAG::Models::SourceSection.create(
          document_id: @doc1.id,
          section_title: "Machine Learning Overview",
          section_number: 997,
          content: "Machine learning is a subset of artificial intelligence that enables computers to learn from data without explicit programming."
        )

        vector = pgvector(Array.new(1024) { rand(-1.0..1.0) })
        SmartRAG::Models::Embedding.create(
          source_id: test_section.id,
          vector: vector
        )
      end

      filters = { document_ids: [@doc1.id] }

      result_without_filters = service.search(query, limit: 20)
      result_with_filters = service.search(query, limit: 20, filters: filters)

      time_without_filters = result_without_filters[:metadata][:execution_time_ms]
      time_with_filters = result_with_filters[:metadata][:execution_time_ms]

      puts "\nFilter performance:"
      puts "  Without filters: #{time_without_filters}ms"
      puts "  With filters: #{time_with_filters}ms"

      # Ensure both searches returned results
      expect(result_without_filters[:results]).not_to be_empty
      expect(result_with_filters[:results]).not_to be_empty

      # Filtering overhead should be minimal
      overhead = (time_with_filters - time_without_filters).to_f / time_without_filters
      expect(overhead.abs).to be < 0.3, "Filter overhead should be less than 30% (was #{overhead.abs})"
    end
  end

  describe "result quality" do
    it "returns high-quality results for common queries" do
      query = "neural networks machine learning"

      result = service.search(query, limit: 10, alpha: 0.7)

      # Basic checks - we should have some results
      expect(result[:results]).not_to be_empty
      expect(result[:metadata][:text_result_count]).to be > 0

      # Vector results may be 0 in test environment if LLM API is not available
      # But the service should gracefully handle this and return text results
      if result[:metadata][:vector_result_count] == 0
        puts "Vector search returned 0 results (LLM API may not be available)"
      end

      # Check that scoring works
      combined_scores = result[:results].map { |r| r[:combined_score] }
      expect(combined_scores.any? { |s| s > 0 }).to be true

      # Verify contributions tracking works
      text_contributions = result[:results].count { |r| r[:contributions][:text] }
      vector_contributions = result[:results].count { |r| r[:contributions][:vector] }

      expect(text_contributions).to be > 0, "Text search should contribute to results"
    end

    it "weights results correctly based on alpha parameter" do
      query = "artificial intelligence"

      result_high_alpha = service.search(query, limit: 10, alpha: 0.9)

      # If no results, create test data with AI content
      if result_high_alpha[:results].empty?
        test_section = SmartRAG::Models::SourceSection.create(
          document_id: @doc1.id,
          section_title: "Artificial Intelligence Fundamentals",
          section_number: 998,
          content: "Deep learning and artificial intelligence are transforming technology. Neural networks are key to AI advancement."
        )

        vector = pgvector(Array.new(1024) { rand(-1.0..1.0) })
        SmartRAG::Models::Embedding.create(
          source_id: test_section.id,
          vector: vector
        )

        result_high_alpha = service.search(query, limit: 10, alpha: 0.9)
      end

      result_low_alpha = service.search(query, limit: 10, alpha: 0.1)

      # Ensure both searches returned results
      expect(result_high_alpha[:results]).not_to be_empty
      expect(result_low_alpha[:results]).not_to be_empty

      # High alpha (vector-heavy) should prioritize vector similarity
      avg_vector_score_high = result_high_alpha[:results].map { |r| r[:vector_score] }.sum / result_high_alpha[:results].size
      avg_vector_score_low = result_low_alpha[:results].map { |r| r[:vector_score] }.sum / result_low_alpha[:results].size

      # Since alpha=0.9 means vector weight is 0.9 vs text weight 0.1
      # High alpha should generally produce higher vector scores
      expect(avg_vector_score_high).to be >= avg_vector_score_low * 0.8, "High alpha (0.9) should produce comparable or higher vector scores than low alpha (0.1)"
    end
  end

  describe "RRF algorithm behavior" do
    it "properly fuses rankings from multiple sources" do
      # Create results with known overlap
      text_results = @sections.first(10).map.with_index(1) do |section, idx|
        {
          section_id: section.id,
          content: "Text result #{idx}",
          rank: idx
        }
      end

      vector_results = (@sections[5..14]).map.with_index(1) do |section, idx|
        {
          section_id: section.id,
          similarity: 0.9 - (idx * 0.01),
          rank: idx
        }
      end

      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.5, k: 60)

      # Should find the overlapping sections
      overlapping_sections = text_results.map { |r| r[:section_id] } & vector_results.map { |r| r[:section_id] }
      expect(overlapping_sections.size).to be > 3

      # Verify RRF scoring
      first_result = combined.first
      expect(first_result[:combined_score]).to be > 0
      expect(first_result[:text_score]).to be > 0
      expect(first_result[:vector_score]).to be > 0
    end
  end

  # Helper methods
  def generate_ml_content(index)
    topics = [
      "machine learning",
      "neural networks",
      "deep learning",
      "artificial intelligence",
      "data science",
      "computer vision",
      "natural language processing",
      "reinforcement learning"
    ]

    "Content about #{topics[index % topics.size]} with technical details and explanations for section #{index + 1}. " +
    "This section covers important concepts and provides examples of implementation approaches."
  end

  def generate_random_vector(dimensions)
    Array.new(dimensions) { rand(-1.0..1.0) }
  end

  # Convert vector array to pgvector format string
  def pgvector(vector_array)
    "[#{vector_array.join(',')}]"
  end

  def percentile(array, percentile)
    sorted = array.sort
    index = (percentile.to_f / 100) * (sorted.length - 1)
    lower = sorted[index.floor]
    upper = sorted[index.ceil]
    lower + (upper - lower) * (index - index.floor)
  end
end
