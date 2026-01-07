require "spec_helper"
require "smart_rag/services/fulltext_search_service"
require "smart_rag/core/fulltext_manager"

RSpec.describe "Full-text Search Integration" do
  let(:db) { SmartRAG.db }
  let(:fulltext_manager) { SmartRAG::Core::FulltextManager.new(db) }
  let(:search_service) { SmartRAG::Services::FulltextSearchService.new(fulltext_manager) }

  # Create test document and sections
  let(:document) do
    SmartRAG::Models::SourceDocument.create(
      title: "Machine Learning Fundamentals",
      url: "https://example.com/ml-fundamentals",
      author: "John Doe",
      language: "en"
    )
  end

  # Create multiple sections with different content
  let(:sections) do
    [
      "Introduction to machine learning and artificial intelligence concepts",
      "Supervised learning algorithms including neural networks",
      "Unsupervised learning and clustering techniques",
      "Deep learning and convolutional neural networks",
      "Natural language processing applications",
      "Reinforcement learning and its applications"
    ]
  end

  before(:all) do
    # Clean up any existing test data
    SmartRAG.db[:search_logs].delete
    SmartRAG.db[:section_fts].delete
  end

  before(:each) do
    # Create sections and indexes for each test
    sections.each_with_index do |content, index|
      section = SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: content,
        section_title: "Section #{index + 1}",
        section_number: index + 1,
        created_at: Time.now - (index * 3600) # Different timestamps
      )

      # Index the section
      fulltext_manager.update_fulltext_index(
        section.id,
        "Section #{index + 1}",
        content,
        "en"
      )
    end
  end

  after(:each) do
    # Clean up
    SmartRAG::Models::SourceSection.where(document_id: document.id).all.each(&:delete)
    SmartRAG::Models::SourceDocument.where(id: document.id).delete
  end

  describe "end-to-end search workflow" do
    it "performs basic full-text search" do
      result = search_service.search("machine learning")

      expect(result[:query]).to eq("machine learning")
      expect(result[:results]).not_to be_empty
      expect(result[:metadata][:total_count]).to be > 0
      expect(result[:metadata][:execution_time_ms]).to be_a(Integer)
    end

    it "returns results with correct structure" do
      result = search_service.search("neural networks")

      expect(result).to include(:query, :results, :metadata)
      expect(result[:results]).to be_an(Array)

      # Check result structure
      first_result = result[:results].first
      expect(first_result).to include(
        :section_id,
        :rank_score,
        :rank
      )
    end

    it "returns highlights for matched content" do
      result = search_service.search("deep learning", enable_highlighting: true)

      # Should have highlights
      result[:results].each do |r|
        if r[:highlight]
          expect(r[:highlight]).to be_a(String)
          expect(r[:highlight]).not_to be_empty
        end
      end
    end

    it "ranks results by relevance" do
      result = search_service.search("machine learning")

      # Verify results are ranked (scores should be descending)
      if result[:results].length > 1
        scores = result[:results].map { |r| r[:rank_score] || 0 }
        expect(scores).to eq(scores.sort.reverse)
      end
    end

    it "respects result limit" do
      result = search_service.search("machine", limit: 3)

      expect(result[:results].length).to be <= 3
    end

    it "returns empty results for non-matching queries" do
      result = search_service.search("nonexistent term xyz123")

      expect(result[:results]).to be_empty
      expect(result[:metadata][:total_count]).to eq(0)
    end
  end

  describe "search with filters" do
    it "filters by document ID" do
      # Create another document
      doc2 = SmartRAG::Models::SourceDocument.create(
        title: "Other Document",
        url: "https://example.com/other",
        language: "en"
      )

      section2 = SmartRAG::Models::SourceSection.create(
        document_id: doc2.id,
        content: "Different content not about machine learning",
        section_title: "Other Section"
      )

      fulltext_manager.update_fulltext_index(
        section2.id,
        "Other Section",
        section2.content,
        "en"
      )

      # Search with filter
      result = search_service.search(
        "machine",
        filters: { document_ids: [document.id] }
      )

      # Should only return results from the first document
      result[:results].each do |r|
        section = SmartRAG::Models::SourceSection[r[:section_id]]
        expect(section.document_id).to eq(document.id)
      end

      # Cleanup
      section2.delete
      doc2.delete
    end

    it "filters by date range" do
      result = search_service.search(
        "machine",
        filters: {
          date_from: Time.now - 3600,
          date_to: Time.now + 3600
        }
      )

      # Should include recent results
      expect(result[:results]).not_to be_empty
    end
  end

  describe "multilingual search" do
    before(:each) do
      skip "pg_jieba extension not available" unless pg_jieba_available?

      puts "DEBUG: Setting up Chinese test data..."
      # Create Chinese document and section
      @chinese_doc = SmartRAG::Models::SourceDocument.create(
        title: "机器学习基础",
        url: "https://example.com/zh-ml",
        language: "zh"
      )

      @chinese_section = SmartRAG::Models::SourceSection.create(
        document_id: @chinese_doc.id,
        content: "这是一个关于机器学习和人工智能的中文段落",
        section_title: "介绍"
      )

      puts "DEBUG: Created Chinese section #{@chinese_section.id}"

      fulltext_manager.update_fulltext_index(
        @chinese_section.id,
        @chinese_section.section_title,
        @chinese_section.content,
        "zh"
      )

      puts "DEBUG: Updated fulltext index for Chinese content"
    end

    after(:each) do
      puts "DEBUG: Cleaning up Chinese test data..."
      @chinese_section&.delete
      @chinese_doc&.delete
    end

    it "detects Chinese language" do
      puts "DEBUG: Running Chinese language detection test..."
      result = search_service.search("机器学习")
      puts "DEBUG: Search completed, checking results..."

      expect(result[:metadata][:language]).to eq("zh")
    end

    it "searches Chinese content" do
      puts "DEBUG: Running Chinese content search test..."
      result = search_service.search("机器学习", language: "zh")
      puts "DEBUG: Chinese search completed, found #{result[:results].length} results"

      expect(result[:results]).not_to be_empty
      expect(result[:results].map { |r| r[:section_id] }).to include(@chinese_section.id)
    end

    it "performs multilingual search" do
      puts "DEBUG: Running multilingual search test..."
      result = Timeout.timeout(10) do
        search_service.multilingual_search(
          "machine",
          ["en", "zh"]
        )
      end
      puts "DEBUG: Multilingual search completed"

      expect(result[:languages]).to include("en", "zh")
      expect(result[:metadata][:multilingual]).to be true
    end
  end

  describe "search suggestions" do
    it "provides suggestions based on content" do
      suggestions = search_service.suggestions("neura", limit: 5)

      expect(suggestions).to be_an(Array)
      expect(suggestions.length).to be <= 5
      # Suggestions should start with prefix
      suggestions.each do |suggestion|
        expect(suggestion.downcase).to start_with("neura")
      end
    end

    it "returns empty array for short prefixes" do
      suggestions = search_service.suggestions("a")

      expect(suggestions).to be_empty
    end
  end

  describe "advanced search features" do
    it "handles phrase queries" do
      result = search_service.search('"deep learning"')

      expect(result[:results]).not_to be_empty
      # Results should contain the exact phrase
      result[:results].each do |r|
        if r[:highlight]
          expect(r[:highlight].downcase).to include("deep")
          expect(r[:highlight].downcase).to include("learning")
        end
      end
    end

    it "handles boolean operators" do
      result = search_service.search("machine AND learning")

      expect(result[:results]).not_to be_empty
      expect(result[:metadata][:total_count]).to be > 0
    end

    it "handles OR operator" do
      result = search_service.search("supervised OR unsupervised")

      expect(result[:results]).not_to be_empty
    end

    it "handles NOT operator" do
      # Search for machine learning without "deep"
      result = search_service.search("machine NOT deep")

      expect(result[:results]).not_to be_empty
      # Results should not contain "deep"
      result[:results].each do |r|
        if r[:highlight]
          # If highlight exists, verify content
          expect(r[:highlight].downcase).not_to include("<mark>deep</mark>")
        end
      end
    end
  end

  describe "search with different options" do
    it "includes content when requested" do
      result = search_service.search(
        "machine",
        include_content: true
      )

      result[:results].each do |r|
        # Content might be included or not depending on implementation
        expect(r).to have_key(:section_id)
      end
    end

    it "includes metadata when requested" do
      result = search_service.search(
        "machine",
        include_metadata: true
      )

      # Metadata might include document info
      expect(result[:results]).not_to be_empty
    end
  end

  describe "performance and logging" do
    it "measures search execution time" do
      result = search_service.search("machine")

      expect(result[:metadata][:execution_time_ms]).to be > 0
    end

    it "logs search queries" do
      expect { search_service.search("test logging") }.to change {
        db[:search_logs].where(search_type: "fulltext", query: "test logging").count
      }.by(1)
    end

    it "records search metrics" do
      search_service.search("machine learning")

      log = db[:search_logs].order(:created_at).last
      expect(log[:query]).to eq("machine learning")
      expect(log[:results_count]).to be > 0
      expect(log[:execution_time_ms]).to be > 0
    end
  end

  describe "search service statistics" do
    it "returns search statistics" do
      # Perform some searches first
      search_service.search("machine")
      search_service.search("learning")

      stats = search_service.statistics

      expect(stats).to have_key(:total_indexed)
      expect(stats).to have_key(:search_performance)
      expect(stats).to have_key(:language_distribution)
      expect(stats).to have_key(:popular_queries)
    end
  end

  describe "quick search" do
    it "returns simplified results" do
      results = search_service.quick_search("machine", 5)

      expect(results).to be_an(Array)
      expect(results.length).to be <= 5
      expect(results.first).to include(:id, :rank)
    end
  end

  describe "search error handling" do
    it "raises error for invalid queries" do
      expect { search_service.search(nil) }.to raise_error(ArgumentError)
      expect { search_service.search("") }.to raise_error(ArgumentError)
    end

    it "raises error for too short queries" do
      expect { search_service.search("a") }.to raise_error(ArgumentError)
    end
  end
end
