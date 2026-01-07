require "spec_helper"
require "smart_rag/core/fulltext_manager"
require "smart_rag/parsers/query_parser"

RSpec.describe SmartRAG::Core::FulltextManager do
  let(:db) { SmartRAG.db }
  let(:query_parser) { SmartRAG::Parsers::QueryParser.new }
  let(:fulltext_manager) { described_class.new(db, query_parser: query_parser) }

  # Create test data
  let(:document) do
    SmartRAG::Models::SourceDocument.create(
      title: "Test Document",
      url: "https://example.com/test",
      language: "en"
    )
  end

  let(:section) do
    SmartRAG::Models::SourceSection.create(
      document_id: document.id,
      content: "This is a test section about machine learning and artificial intelligence.",
      section_title: "Machine Learning Basics",
      section_number: 1
    )
  end

  before(:each) do
    # Clean up before each test
    db[:section_fts].delete
    db[:source_sections].delete
    db[:search_logs].delete
  end

  describe "#initialize" do
    it "initializes with database connection" do
      expect(fulltext_manager.db).to eq(db)
      expect(fulltext_manager.query_parser).to be_a(SmartRAG::Parsers::QueryParser)
    end

    it "accepts custom logger" do
      logger = Logger.new(StringIO.new)
      manager = described_class.new(db, query_parser: query_parser, logger: logger)
      expect(manager.logger).to eq(logger)
    end

    it "has default config" do
      expect(fulltext_manager.instance_variable_get(:@config)).to include(
        max_results: 100,
        default_language: "en"
      )
    end
  end

  describe "#update_fulltext_index" do
    it "creates new fulltext index" do
      result = fulltext_manager.update_fulltext_index(
        section.id,
        "Machine Learning",
        "Content about AI and machine learning",
        "en"
      )

      expect(result).to be true
      expect(db[:section_fts].where(section_id: section.id).count).to eq(1)
    end

    it "updates existing index" do
      # Create first
      fulltext_manager.update_fulltext_index(
        section.id,
        "Old Title",
        "Old content",
        "en"
      )

      # Update
      fulltext_manager.update_fulltext_index(
        section.id,
        "New Title",
        "New content about deep learning",
        "en"
      )

      # Should still have one record
      expect(db[:section_fts].where(section_id: section.id).count).to eq(1)

      # Check content updated
      index = db[:section_fts].where(section_id: section.id).first
      expect(index).not_to be_nil
    end

    it "handles empty title" do
      result = fulltext_manager.update_fulltext_index(
        section.id,
        "",
        "Content without title",
        "en"
      )

      expect(result).to be true
      expect(db[:section_fts].where(section_id: section.id).count).to eq(1)
    end

    it "handles Chinese content" do
      skip "pg_jieba extension not available" unless pg_jieba_available?

      china_section = SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: "这是一个关于机器学习和人工智能的测试段落",
        section_title: "机器学习基础",
        section_number: 2
      )

      result = fulltext_manager.update_fulltext_index(
        china_section.id,
        "机器学习",
        "这是一个关于机器学习和人工智能的测试段落",
        "zh"
      )

      expect(result).to be true
    end

    it "raises error for nil section_id" do
      expect {
        fulltext_manager.update_fulltext_index(nil, "Title", "Content")
      }.to raise_error(ArgumentError, "Section ID cannot be nil")
    end

    it "raises error for nil content" do
      expect {
        fulltext_manager.update_fulltext_index(section.id, "Title", nil)
      }.to raise_error(ArgumentError, "Content cannot be nil")
    end
  end

  describe "#batch_update_fulltext" do
    it "updates multiple indexes" do
      sections_data = [
        {
          id: section.id,
          title: "Section 1",
          content: "Content 1",
          language: "en"
        }
      ]

      # Create another section
      section2 = SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: "Second section content",
        section_title: "Section 2",
        section_number: 2
      )

      sections_data << {
        id: section2.id,
        title: "Section 2",
        content: "Content 2",
        language: "en"
      }

      results = fulltext_manager.batch_update_fulltext(sections_data)

      expect(results[:success]).to eq(2)
      expect(results[:failed]).to eq(0)
      expect(results[:errors]).to be_empty
    end

    it "continues on individual failures" do
      sections_data = [
        {
          id: section.id,
          title: "Valid section",
          content: "Valid content",
          language: "en"
        },
        {
          id: nil,
          title: "Invalid section",
          content: "Invalid content",
          language: "en"
        }
      ]

      results = fulltext_manager.batch_update_fulltext(sections_data)

      expect(results[:success]).to eq(1)
      expect(results[:failed]).to eq(1)
      expect(results[:errors].length).to eq(1)
    end

    it "handles empty array" do
      results = fulltext_manager.batch_update_fulltext([])

      expect(results[:success]).to eq(0)
      expect(results[:failed]).to eq(0)
      expect(results[:errors]).to be_empty
    end
  end

  describe "#search_by_text" do
    before(:each) do
      # Create test indexes
      fulltext_manager.update_fulltext_index(
        section.id,
        "Machine Learning Basics",
        "This is a test section about machine learning and artificial intelligence.",
        "en"
      )
    end

    it "searches for matching content" do
      results = fulltext_manager.search_by_text("machine learning", "en", 10)

      expect(results).not_to be_empty
      expect(results.first[:section_id]).to eq(section.id)
    end

    it "returns empty array for no matches" do
      results = fulltext_manager.search_by_text("nonexistent term", "en", 10)

      expect(results).to be_empty
    end

    it "respects limit parameter" do
      # Create more sections
      5.times do |i|
        s = SmartRAG::Models::SourceSection.create(
          document_id: document.id,
          content: "Content about machine learning #{i}",
          section_title: "Section #{i}",
          section_number: i + 1
        )
        fulltext_manager.update_fulltext_index(
          s.id,
          "Section #{i}",
          "Content about machine learning #{i}",
          "en"
        )
      end

      results = fulltext_manager.search_by_text("machine learning", "en", 3)

      expect(results.length).to be <= 3
    end

    it "auto-detects language" do
      results = fulltext_manager.search_by_text("machine learning", nil, 10)

      expect(results).not_to be_empty
    end

    it "returns ranked results" do
      results = fulltext_manager.search_by_text("machine learning", "en", 10)

      expect(results.all? { |r| r[:rank_score].is_a?(Numeric) }).to be true
      # Check if sorted by rank (descending)
      ranks = results.map { |r| r[:rank_score] }
      expect(ranks).to eq(ranks.sort.reverse)
    end

    it "returns highlights" do
      results = fulltext_manager.search_by_text("machine learning", "en", 10)

      expect(results.first[:highlight]).not_to be_empty
      expect(results.first[:highlight]).to be_a(String)
    end

    it "applies filters" do
      results = fulltext_manager.search_by_text(
        "machine learning",
        "en",
        10,
        filters: { document_ids: [document.id] }
      )

      expect(results).not_to be_empty
    end

    it "raises error for nil query" do
      expect {
        fulltext_manager.search_by_text(nil, "en", 10)
      }.to raise_error(ArgumentError, "Query cannot be nil")
    end

    it "logs search query" do
      expect(fulltext_manager.logger).to receive(:info).with(/Full-text search returned/)

      fulltext_manager.search_by_text("machine learning", "en", 10)
    end

    it "handles search errors gracefully" do
      allow(fulltext_manager.db).to receive(:[]).and_raise(StandardError.new("DB error"))

      expect {
        fulltext_manager.search_by_text("test", "en", 10)
      }.to raise_error(SmartRAG::Errors::FulltextSearchError)
    end
  end

  describe "#search_with_filters" do
    before(:each) do
      fulltext_manager.update_fulltext_index(
        section.id,
        "ML Section",
        "Machine learning content",
        "en"
      )
    end

    it "filters by document ID" do
      results = fulltext_manager.search_with_filters(
        "machine",
        { document_ids: [document.id] }
      )

      expect(results).not_to be_empty
    end

    it "filters by non-existent document ID" do
      results = fulltext_manager.search_with_filters(
        "machine",
        { document_ids: [99999] }
      )

      expect(results).to be_empty
    end

    it "combines multiple filters" do
      results = fulltext_manager.search_with_filters(
        "machine",
        {
          document_ids: [document.id],
          date_from: Time.now - 86400
        }
      )

      expect(results).not_to be_empty
    end
  end

  describe "#detect_language" do
    it "delegates to query parser" do
      expect(query_parser).to receive(:detect_language).with("test").and_return("zh")

      result = fulltext_manager.detect_language("test")
      expect(result).to eq("zh")
    end

    it "detects Chinese correctly" do
      result = fulltext_manager.detect_language("中文测试")
      expect(result).to eq("zh")
    end
  end

  describe "#build_tsquery" do
    it "delegates to query parser" do
      expect(query_parser).to receive(:build_tsquery).with("test", "en").and_return("tsquery")

      result = fulltext_manager.build_tsquery("test", "en")
      expect(result).to eq("tsquery")
    end
  end

  describe "#parse_advanced_query" do
    it "delegates to query parser" do
      parsed = { original: "test", phrases: [] }
      expect(query_parser).to receive(:parse_advanced_query).with("test").and_return(parsed)

      result = fulltext_manager.parse_advanced_query("test")
      expect(result).to eq(parsed)
    end
  end

  describe "#stats" do
    it "returns statistics" do
      stats = fulltext_manager.stats

      expect(stats).to have_key(:total_indexed)
      expect(stats).to have_key(:languages)
      expect(stats).to have_key(:last_updated)
    end

    it "returns correct counts" do
      fulltext_manager.update_fulltext_index(section.id, "Title", "Content", "en")

      stats = fulltext_manager.stats

      expect(stats[:total_indexed]).to eq(1)
      expect(stats[:languages]).to include("en")
    end
  end

  describe "#remove_index" do
    before(:each) do
      fulltext_manager.update_fulltext_index(section.id, "Title", "Content", "en")
    end

    it "removes existing index" do
      result = fulltext_manager.remove_index(section.id)

      expect(result).to be true
      expect(db[:section_fts].where(section_id: section.id).count).to eq(0)
    end

    it "returns false for non-existent index" do
      result = fulltext_manager.remove_index(99999)

      expect(result).to be false
    end

    it "raises error for nil section_id" do
      expect {
        fulltext_manager.remove_index(nil)
      }.to raise_error(ArgumentError, "Section ID cannot be nil")
    end
  end

  describe "#cleanup_orphaned_indexes" do
    it "removes indexes for deleted sections" do
      # Create section and index
      s = SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: "Content to be deleted",
        section_title: "To Delete"
      )
      fulltext_manager.update_fulltext_index(s.id, "Title", "Content", "en")

      # Delete section (won't cascade to section_fts in test setup)
      s.delete

      # Clean up
      count = fulltext_manager.cleanup_orphaned_indexes

      expect(count).to eq(1)
      expect(db[:section_fts].where(section_id: s.id).count).to eq(0)
    end
  end

  describe "private methods" do
    describe "#apply_search_filters" do
      it "returns dataset unchanged without filters" do
        dataset = db[:section_fts]
        filtered = fulltext_manager.send(:apply_search_filters, dataset, {})

        expect(filtered).to eq(dataset)
      end
    end

    describe "#get_text_search_config" do
      it "returns config for language" do
        config = fulltext_manager.send(:get_text_search_config, "en")
        expect(config).to eq("pg_catalog.english")
      end

      it "returns simple config for unknown language" do
        config = fulltext_manager.send(:get_text_search_config, "unknown")
        expect(config).to eq("pg_catalog.simple")
      end
    end

    describe "#setweight" do
      it "returns setweight SQL for non-empty vector" do
        result = fulltext_manager.send(:setweight, "vector", "A")
        expect(result).to include("setweight")
        expect(result).to include("'A'")
      end

      it "returns empty string for nil vector" do
        result = fulltext_manager.send(:setweight, nil, "A")
        expect(result).to be_empty
      end
    end

    describe "#to_tsvector" do
      it "escapes quotes in text" do
        result = fulltext_manager.send(:to_tsvector, "english", "can't stop")
        expect(result).to include("''") # SQL escaped quotes
      end
    end

    describe "#format_search_result" do
      it "formats result correctly" do
        row = {
          section_id: 1,
          language: "en",
          rank_score: 0.95,
          highlight: "Test highlight"
        }

        formatted = fulltext_manager.send(:format_search_result, row, "query")

        expect(formatted[:section_id]).to eq(1)
        expect(formatted[:language]).to eq("en")
        expect(formatted[:rank_score]).to eq(0.95)
        expect(formatted[:highlight]).to eq("Test highlight")
        expect(formatted[:query]).to eq("query")
      end
    end

    describe "#combine_results_with_rrf" do
      let(:text_results) do
        [
          { section_id: 1, rank_score: 0.9 },
          { section_id: 2, rank_score: 0.8 }
        ]
      end

      let(:vector_results) do
        [
          { section_id: 2, rank_score: 0.85 },
          { section_id: 3, rank_score: 0.95 }
        ]
      end

      it "combines results using RRF" do
        combined = fulltext_manager.send(:combine_results_with_rrf, text_results, vector_results, k: 60)

        expect(combined.length).to eq(3)
        expect(combined.map { |r| r[:section_id] }).to include(1, 2, 3)
      end

      it "ranks combined results by RRF score" do
        combined = fulltext_manager.send(:combine_results_with_rrf, text_results, vector_results, k: 60)

        # Section 2 should rank higher (appears in both results)
        section_2_pos = combined.index { |r| r[:section_id] == 2 }
        section_1_pos = combined.index { |r| r[:section_id] == 1 }

        expect(section_2_pos).to be < section_1_pos
      end

      it "handles empty results" do
        combined = fulltext_manager.send(:combine_results_with_rrf, [], [], k: 60)
        expect(combined).to be_empty
      end
    end
  end
end
