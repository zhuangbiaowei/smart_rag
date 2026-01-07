require "spec_helper"
require "smart_rag/core/query_processor"
require "smart_rag/services/embedding_service"
require "smart_rag/services/tag_service"
require "smart_rag/services/vector_search_service"
require "smart_rag/services/fulltext_search_service"
require "smart_rag/services/hybrid_search_service"
require "smart_rag/services/summarization_service"
require "smart_rag/models/source_document"
require "smart_rag/models/source_section"
require "smart_rag/models/tag"

RSpec.describe SmartRAG::Core::QueryProcessor do
  let(:config) { { logger: Logger.new(nil) } }
  let(:mock_embedding_service) { instance_double("SmartRAG::Services::EmbeddingService") }
  let(:mock_tag_service) { instance_double("SmartRAG::Services::TagService") }
  let(:mock_embedding_manager) { instance_double("SmartRAG::Core::Embedding") }
  let(:mock_vector_search_service) { instance_double("SmartRAG::Services::VectorSearchService") }
  let(:mock_fulltext_search_service) { instance_double("SmartRAG::Services::FulltextSearchService") }
  let(:mock_hybrid_search_service) { instance_double("SmartRAG::Services::HybridSearchService") }
  let(:mock_summarization_service) { instance_double("SmartRAG::Services::SummarizationService") }

  let(:query_processor) do
    described_class.new(
      embedding_service: mock_embedding_service,
      tag_service: mock_tag_service,
      embedding_manager: mock_embedding_manager,
      vector_search_service: mock_vector_search_service,
      fulltext_search_service: mock_fulltext_search_service,
      hybrid_search_service: mock_hybrid_search_service,
      summarization_service: mock_summarization_service,
      logger: Logger.new(nil)
    )
  end

  let(:query_vector) { Array.new(1024) { |i| Math.sin(i * 0.01) * 0.5 } }

  describe "#initialize" do
    it "initializes with all services" do
      expect(query_processor.embedding_service).to eq(mock_embedding_service)
      expect(query_processor.tag_service).to eq(mock_tag_service)
      expect(query_processor.vector_search_service).to eq(mock_vector_search_service)
      expect(query_processor.summarization_service).to eq(mock_summarization_service)
    end

    it "creates default services when not provided" do
      expect { described_class.new(logger: Logger.new(nil)) }.not_to raise_error
    end
  end

  describe "#process_query" do
    let(:document) { SmartRAG::Models::SourceDocument.create!(title: "Test Doc", url: "https://test.com") }
    let(:section) do
      document.add_section(
        content: "Machine learning is a subset of artificial intelligence.",
        section_number: 1
      )
    end

    before do
      allow(mock_embedding_service).to receive(:generate_embedding).and_return(query_vector)
    end

    context "with vector search" do
      let(:search_results) do
        [
          {
            embedding: double("Embedding", section: section),
            section: section,
            similarity: 0.95
          }
        ]
      end

      before do
        allow(mock_vector_search_service).to receive(:search_by_vector).and_return(search_results)
      end

      it "processes a query and returns results" do
        results = query_processor.process_query(
          "What is machine learning?",
          search_type: :vector,
          limit: 5
        )

        expect(results).to have_key(:results)
        expect(results).to have_key(:search_type)
        expect(results[:search_type]).to eq(:vector)
        expect(results[:results]).not_to be_empty
      end

      it "validates query text is not nil" do
        expect { query_processor.process_query(nil) }.to raise_error(ArgumentError, /Query text cannot be nil/)
      end

      it "validates query text is not empty" do
        expect { query_processor.process_query("") }.to raise_error(ArgumentError, /Query text cannot be nil/)
      end

      it "validates query text is not whitespace" do
        expect { query_processor.process_query("   ") }.to raise_error(ArgumentError, /Query text cannot be nil/)
      end
    end

    context "with fulltext search" do
      let(:search_results) do
        [
          {
            section: section,
            title_highlight: "Machine learning",
            content_highlight: "Machine learning is a subset of artificial intelligence",
            rank: 1
          }
        ]
      end

      before do
        allow(mock_fulltext_search_service).to receive(:search).and_return(search_results)
      end

      it "processes a query with fulltext search" do
        results = query_processor.process_query(
          "machine learning",
          search_type: :fulltext,
          limit: 5
        )

        expect(results[:search_type]).to eq(:fulltext)
        expect(results[:results]).not_to be_empty
      end
    end

    context "with hybrid search" do
      let(:search_results) do
        [
          {
            section: section,
            similarity: 0.92,
            rank: 1,
            combined_score: 0.045
          }
        ]
      end

      before do
        allow(mock_hybrid_search_service).to receive(:search).and_return(search_results)
      end

      it "processes a query with hybrid search" do
        results = query_processor.process_query(
          "What is machine learning?",
          search_type: :hybrid,
          limit: 5
        )

        expect(results[:search_type]).to eq(:hybrid)
        expect(results[:results]).not_to be_empty
      end
    end

    context "with tag generation" do
      let(:generated_tags) { { content_tags: ["machine learning", "AI"] } }
      let(:tag) { SmartRAG::Models::Tag.create!(name: "machine learning") }

      before do
        allow(mock_tag_service).to receive(:generate_tags).and_return(generated_tags)
        allow(mock_embedding_manager).to receive(:search_by_vector_with_tags).and_return([])
        allow(SmartRAG::Models::Tag).to receive(:find).and_return(tag)
      end

      it "generates tags from query when requested" do
        results = query_processor.process_query(
          "Tell me about machine learning and AI",
          search_type: :vector,
          generate_tags: true,
          limit: 5
        )

        expect(mock_tag_service).to have_received(:generate_tags).with(
          "Tell me about machine learning and AI",
          nil,
          [:en],
          hash_including(max_content_tags: 5)
        )
      end
    end

    context "with document filtering" do
      let(:search_results) { [] }

      before do
        allow(mock_vector_search_service).to receive(:search_by_vector).and_return(search_results)
      end

      it "filters results by document IDs" do
        query_processor.process_query(
          "machine learning",
          search_type: :vector,
          document_ids: [1, 2, 3]
        )

        expect(mock_vector_search_service).to have_received(:search_by_vector).with(
          anything,
          hash_including(document_ids: [1, 2, 3])
        )
      end
    end

    context "with invalid search type" do
      it "raises ArgumentError" do
        expect {
          query_processor.process_query("test", search_type: :invalid)
        }.to raise_error(ArgumentError, "Invalid search type: invalid")
      end
    end
  end

  describe "#generate_response" do
    let(:question) { "What is machine learning?" }
    let(:document) { SmartRAG::Models::SourceDocument.create!(title: "ML Guide", url: "https://ml.com") }
    let(:section) do
      document.add_section(
        content: "Machine learning is a subset of AI that enables computers to learn.",
        section_title: "Introduction to ML",
        section_number: 1
      )
    end

    let(:search_results) do
      {
        results: [
          {
            section: section,
            similarity: 0.95,
            embedding: double("Embedding")
          }
        ],
        search_type: :hybrid
      }
    end

    let(:generated_response) do
      {
        answer: "Machine learning is a subset of artificial intelligence.",
        confidence: 0.92,
        sources: [
          {
            document_id: document.id,
            document_title: document.title,
            section_id: section.id,
            section_title: section.section_title
          }
        ]
      }
    end

    before do
      allow(mock_summarization_service).to receive(:summarize_search_results).and_return(
        answer: "Machine learning is a subset of artificial intelligence.",
        confidence: 0.92
      )
    end

    it "generates a response from search results" do
      response = query_processor.generate_response(question, search_results)

      expect(response).to have_key(:answer)
      expect(response[:answer]).to include("Machine learning")
      expect(response).to have_key(:confidence)
    end

    it "validates question is not nil" do
      expect {
        query_processor.generate_response(nil, search_results)
      }.to raise_error(ArgumentError, /Question cannot be nil/)
    end

    it "validates question is not empty" do
      expect {
        query_processor.generate_response("", search_results)
      }.to raise_error(ArgumentError, /Question cannot be nil/)
    end

    it "validates search results are not nil" do
      expect {
        query_processor.generate_response(question, nil)
      }.to raise_error(ArgumentError, /Search results cannot be nil/)
    end

    context "with empty search results" do
      let(:empty_results) { { results: [] } }

      it "returns a message indicating insufficient information" do
        response = query_processor.generate_response(question, empty_results)

        expect(response[:answer]).to include("don't have enough information")
        expect(response[:confidence]).to eq(0.0)
        expect(response[:sources]).to be_empty
      end
    end

    context "with sources" do
      it "includes source references" do
        response = query_processor.generate_response(
          question,
          search_results,
          include_sources: true
        )

        expect(response).to have_key(:sources)
        expect(response[:sources]).not_to be_empty
        expect(response[:sources].first).to have_key(:document_id)
        expect(response[:sources].first).to have_key(:section_title)
      end

      it "can disable source references" do
        response = query_processor.generate_response(
          question,
          search_results,
          include_sources: false
        )

        expect(response[:sources]).to be_nil
      end
    end
  end

  describe "#ask" do
    let(:question) { "What is machine learning?" }
    let(:search_results) { { results: [], search_type: :hybrid, total_results: 0 } }
    let(:response) { { answer: "Test answer", confidence: 0.9, sources: [] } }

    before do
      allow(query_processor).to receive(:process_query).and_return(search_results)
      allow(query_processor).to receive(:generate_response).and_return(response)
    end

    it "processes query and generates response" do
      result = query_processor.ask(question)

      expect(result[:question]).to eq(question)
      expect(result[:answer]).to eq("Test answer")
      expect(result).to have_key(:sources)
      expect(result).to have_key(:metadata)
    end

    it "passes options to process_query" do
      query_processor.ask(question, search_type: :vector, limit: 5)

      expect(query_processor).to have_received(:process_query).with(
        question,
        hash_including(search_type: :vector, limit: 5)
      )
    end

    it "passes options to generate_response" do
      query_processor.ask(question, include_sources: false)

      expect(query_processor).to have_received(:generate_response).with(
        question,
        anything,
        hash_including(include_sources: false)
      )
    end

    context "when processing fails" do
      before do
        allow(query_processor).to receive(:process_query).and_raise(StandardError, "Search failed")
      end

      it "raises error" do
        expect { query_processor.ask(question) }.to raise_error(StandardError, /Search failed/)
      end
    end
  end

  describe "language detection" do
    describe "#detect_language" do
      it "detects Chinese (Simplified)" do
        result = query_processor.send(:detect_language, "机器学习是什么？")
        expect(result).to eq(:zh_cn)
      end

      it "detects Japanese" do
        result = query_processor.send(:detect_language, "機械学習とは何ですか？")
        expect(result).to eq(:ja)
      end

      it "defaults to English for Latin text" do
        result = query_processor.send(:detect_language, "What is machine learning?")
        expect(result).to eq(:en)
      end
    end
  end

  describe "#ensure_tag_objects" do
    let(:tag1) { SmartRAG::Models::Tag.create!(name: "AI") }
    let(:tag2) { SmartRAG::Models::Tag.create!(name: "ML") }

    it "converts tag IDs to tag objects" do
      tags = query_processor.send(:ensure_tag_objects, [tag1.id, tag2.id])
      expect(tags).to all(be_a(SmartRAG::Models::Tag))
    end

    it "keeps tag objects as-is" do
      tags = query_processor.send(:ensure_tag_objects, [tag1, tag2])
      expect(tags).to eq([tag1, tag2])
    end

    it "converts tag names to tag objects" do
      tags = query_processor.send(:ensure_tag_objects, ["AI", "ML"])
      expect(tags).to all(be_a(SmartRAG::Models::Tag))
    end

    it "raises error for invalid tag type" do
      expect {
        query_processor.send(:ensure_tag_objects, [123.45])
      }.to raise_error(ArgumentError, /Invalid tag type/)
    end

    it "handles empty input" do
      tags = query_processor.send(:ensure_tag_objects, [])
      expect(tags).to be_empty
    end
  end

  describe "#extract_context_for_response" do
    let(:document) { SmartRAG::Models::SourceDocument.create!(title: "Test", url: "https://test.com") }
    let(:section) do
      document.add_section(
        content: "Machine learning enables computers to learn from data.",
        section_title: "ML Basics",
        section_number: 1
      )
    end

    it "extracts context from search results" do
      results = [
        {
          section: section,
          similarity: 0.95
        }
      ]

      context = query_processor.send(:extract_context_for_response, results)

      expect(context).to include("Machine learning")
      expect(context).to include("ML Basics")
    end

    it "truncates context if too long" do
      long_content = "x" * 5000
      section.update(content: long_content)

      results = [
        {
          section: section,
          similarity: 0.95
        }
      ]

      context = query_processor.send(:extract_context_for_response, results)

      expect(context.length).to be < 5000
      expect(context).to include("(truncated)")
    end
  end

  describe "#extract_sources" do
    let(:document) { SmartRAG::Models::SourceDocument.create!(title: "ML Guide", url: "https://ml.com") }
    let(:section) do
      document.add_section(
        content: "Test content",
        section_title: "Section 1",
        section_number: 1
      )
    end

    it "extracts source information from results" do
      results = [
        {
          section: section,
          similarity: 0.95
        }
      ]

      sources = query_processor.send(:extract_sources, results)

      expect(sources).not_to be_empty
      expect(sources.first).to have_key(:document_id)
      expect(sources.first).to have_key(:document_title)
      expect(sources.first).to have_key(:section_title)
      expect(sources.first).to have_key(:url)
    end
  end
end
