require "spec_helper"
require "smart_rag/core/query_processor"
require "smart_rag/models/source_document"
require "smart_rag/models/source_section"
require "smart_rag/models/embedding"

RSpec.describe "Natural language query processing integration", type: :integration do
  let(:query_processor) { SmartRAG::Core::QueryProcessor.new(
    logger: Logger.new(nil),
    summarization_service: mock_summarization_service
  ) }
  let(:embedding_manager) { SmartRAG::Core::Embedding.new }

  # Mock smart_prompt engine for consistent test results
  let(:mock_smart_prompt) { instance_double("SmartPrompt::Engine") }
  let(:mock_embedding_service) { instance_double("SmartRAG::Services::EmbeddingService") }
  let(:mock_summarization_service) { instance_double("SmartRAG::Services::SummarizationService") }
  let(:mock_hybrid_search_service) { instance_double("SmartRAG::Services::HybridSearchService") }

  before do
    # Mock the smart_prompt engine to avoid actual LLM calls
    allow(SmartPrompt::Engine).to receive(:new).and_return(mock_smart_prompt)
    allow(mock_smart_prompt).to receive(:call_worker).and_return(
      {
        "answer" => "Machine learning is a subset of AI that enables computers to learn from data.",
        "confidence" => 0.92
      }.to_json
    )

    # Mock embedding generation to return a valid vector
    allow(SmartRAG::Services::EmbeddingService).to receive(:new).and_return(mock_embedding_service)
    allow(mock_embedding_service).to receive(:generate_embedding).and_return(
      Array.new(1024) { |i| Math.sin(i * 0.01) * 0.5 }
    )

    # Mock hybrid search service
    allow(SmartRAG::Services::HybridSearchService).to receive(:new).and_return(mock_hybrid_search_service)
    allow(mock_hybrid_search_service).to receive(:search).and_return(
      results: [
        {
          section: instance_double("SmartRAG::Models::SourceSection",
            id: 1,
            content: "Machine learning is a subset of artificial intelligence.",
            section_title: "Introduction to Machine Learning",
            document_id: 1,
            document: instance_double("SmartRAG::Models::SourceDocument",
              id: 1,
              title: "Machine Learning Fundamentals",
              url: "https://example.com/ml-fundamentals"
            )
          ),
          similarity: 0.92,
          combined_score: 0.045,
          contributions: { text: true, vector: true }
        }
      ],
      metadata: { total_count: 1 }
    )

    # Mock summarization service - return different answers based on question
    allow(SmartRAG::Services::SummarizationService).to receive(:new).and_return(mock_summarization_service)
    allow(mock_summarization_service).to receive(:summarize_search_results) do |question, context, options|
      if question.include?("deep learning")
        {
          answer: "Deep learning is a specialized area of machine learning that uses neural networks with multiple layers to process complex data patterns.",
          confidence: 0.95
        }
      else
        {
          answer: "Machine learning is a subset of AI that enables computers to learn from data.",
          confidence: 0.92
        }
      end
    end
  end

  describe "end-to-end query processing" do
    let(:document) do
      SmartRAG::Models::SourceDocument.create!(
        title: "Machine Learning Fundamentals",
        url: "https://example.com/ml-fundamentals",
        author: "John Doe"
      )
    end

    let(:section1) do
      document.add_section(
        content: "Machine learning is a subset of artificial intelligence that enables computers to learn from data without being explicitly programmed. It uses algorithms to identify patterns and make predictions.",
        section_title: "Introduction to Machine Learning",
        section_number: 1
      )
    end

    let(:section2) do
      document.add_section(
        content: "Deep learning is a specialized area of machine learning that uses neural networks with multiple layers. These deep neural networks can process complex patterns in large datasets.",
        section_title: "Deep Learning Overview",
        section_number: 2
      )
    end

    before do
      # Create embeddings for the sections
      create_test_embedding(section1, query_similar: true)
      create_test_embedding(section2, query_similar: false)
    end

    describe "#process_query" do
      it "processes natural language query and returns search results" do
        results = query_processor.process_query(
          "What is machine learning?",
          search_type: :vector,
          limit: 10
        )

        expect(results).to have_key(:results)
        expect(results).to have_key(:search_type)
        expect(results).to have_key(:total_results)

        expect(results[:results]).not_to be_empty
        expect(results[:results].first).to have_key(:section)
        expect(results[:results].first).to have_key(:similarity)
      end

      it "performs hybrid search combining vector and fulltext" do
        results = query_processor.process_query(
          "machine learning artificial intelligence",
          search_type: :hybrid,
          limit: 10
        )

        expect(results[:search_type]).to eq(:hybrid)
        expect(results[:results]).not_to be_empty
      end

      it "handles fulltext search for keyword queries" do
        results = query_processor.process_query(
          "deep learning neural networks",
          search_type: :fulltext,
          limit: 10
        )

        expect(results[:search_type]).to eq(:fulltext)
        expect(results[:results]).not_to be_empty
      end

      it "limits results based on limit parameter" do
        results = query_processor.process_query(
          "machine learning",
          search_type: :vector,
          limit: 1
        )

        expect(results[:results].size).to eq(1)
      end

      it "filters results by document ID" do
        # Create another document
        other_doc = SmartRAG::Models::SourceDocument.create!(
          title: "Other Document",
          url: "https://other.com"
        )
        other_section = other_doc.add_section(
          content: "This is about something else entirely.",
          section_number: 1
        )
        create_test_embedding(other_section, query_similar: false)

        # Search only in the main document
        results = query_processor.process_query(
          "machine learning",
          search_type: :vector,
          document_ids: [document.id],
          limit: 10
        )

        # All results should be from the specified document
        results[:results].each do |result|
          expect(result[:section].document_id).to eq(document.id)
        end
      end
    end

    describe "#generate_response" do
      let(:search_results) do
        query_processor.process_query("What is machine learning?", search_type: :vector, limit: 5)
      end

      it "generates natural language response from search results" do
        response = query_processor.generate_response(
          "What is machine learning?",
          search_results,
          include_sources: true
        )

        expect(response).to have_key(:answer)
        expect(response).to have_key(:confidence)
        expect(response[:answer]).to be_a(String)
        expect(response[:answer].length).to be > 0
        expect(response[:confidence]).to be_between(0.0, 1.0)
      end

      it "includes source references when requested" do
        response = query_processor.generate_response(
          "What is machine learning?",
          search_results,
          include_sources: true
        )

        expect(response).to have_key(:sources)
        expect(response[:sources]).to be_an(Array)

        if response[:sources].any?
          source = response[:sources].first
          expect(source).to have_key(:document_title)
          expect(source).to have_key(:section_title)
          expect(source).to have_key(:document_id)
          expect(source).to have_key(:section_id)
        end
      end

      it "excludes sources when not requested" do
        response = query_processor.generate_response(
          "What is machine learning?",
          search_results,
          include_sources: false
        )

        expect(response[:sources]).to be_nil
      end

      it "handles questions with no relevant results" do
        irrelevant_results = { results: [] }

        response = query_processor.generate_response(
          "What is quantum computing?",
          irrelevant_results
        )

        expect(response[:answer]).to include("don't have enough information")
        expect(response[:confidence]).to eq(0.0)
        expect(response[:sources]).to be_empty
      end
    end

    describe "#ask" do
      it "processes query and generates response in one step" do
        result = query_processor.ask("What is machine learning?", search_type: :vector)

        expect(result).to have_key(:question)
        expect(result).to have_key(:answer)
        expect(result).to have_key(:sources)
        expect(result).to have_key(:search_results)
        expect(result).to have_key(:metadata)

        expect(result[:question]).to eq("What is machine learning?")
        expect(result[:answer]).to be_a(String)
        expect(result[:answer].length).to be > 0
      end

      it "includes metadata about the search" do
        result = query_processor.ask("machine learning applications", search_type: :hybrid)

        metadata = result[:metadata]
        expect(metadata).to have_key(:search_type)
        expect(metadata).to have_key(:total_results)
        expect(metadata[:search_type]).to eq(:hybrid)
        expect(metadata[:total_results]).to be >= 0
      end
    end

    describe "multilingual support" do
      before do
        # Create document with Chinese content
        @chinese_doc = SmartRAG::Models::SourceDocument.create!(
          title: "机器学习基础",
          url: "https://example.com/ml-zh"
        )
        @chinese_section = @chinese_doc.add_section(
          content: "机器学习是人工智能的一个重要分支。它使计算机能够从数据中学习，而无需显式编程。",
          section_title: "机器学习介绍",
          section_number: 1
        )
        create_test_embedding(@chinese_section, query_similar: true)
      end

      it "processes Chinese queries" do
        results = query_processor.process_query(
          "什么是机器学习？",
          search_type: :vector,
          language: :zh_cn,
          limit: 5
        )

        expect(results[:results]).not_to be_empty
      end

      it "detects language from query text" do
        # This would use the auto-detection in real implementation
        expect(query_processor.send(:detect_language, "机器学习是什么？")).to eq(:zh_cn)
        expect(query_processor.send(:detect_language, "What is machine learning?")).to eq(:en)
        expect(query_processor.send(:detect_language, "機械学習とは何ですか？")).to eq(:ja)
      end

      it "generates responses in multiple languages" do
        search_results = query_processor.process_query("机器学习", search_type: :vector)

        # English response
        en_response = query_processor.generate_response(
          "What is machine learning?",
          search_results,
          language: :en
        )
        expect(en_response[:answer]).to be_a(String)

        # Chinese response
        zh_response = query_processor.generate_response(
          "什么是机器学习？",
          search_results,
          language: :zh_cn
        )
        expect(zh_response[:answer]).to be_a(String)
      end
    end

    describe "tag integration" do
      let(:ai_tag) { SmartRAG::Models::Tag.create!(name: "AI") }
      let(:ml_tag) { SmartRAG::Models::Tag.create!(name: "Machine Learning") }

      before do
        section1.add_tag(ai_tag)
        section1.add_tag(ml_tag)
      end

      it "boosts results based on matching tags" do
        results = query_processor.process_query(
          "artificial intelligence",
          search_type: :vector,
          tags: [ai_tag, ml_tag],
          limit: 10
        )

        expect(results[:results]).not_to be_empty

        # Check if tag boosting was applied
        if results[:results].any? { |r| r[:tag_boost] }
          boosted_results = results[:results].select { |r| r[:tag_boost] && r[:tag_boost] > 0 }
          expect(boosted_results).not_to be_empty
        end
      end

      it "generates tags from query when requested" do
        expect_any_instance_of(SmartRAG::Services::TagService).to receive(:generate_tags).and_return(
          { content_tags: ["machine learning", "AI"] }
        )

        results = query_processor.process_query(
          "Tell me about machine learning and AI",
          search_type: :vector,
          generate_tags: true,
          limit: 10
        )

        expect(results[:results]).not_to be_empty
      end
    end

    describe "error handling" do
      it "handles invalid search type gracefully" do
        expect {
          query_processor.process_query("test", search_type: :invalid)
        }.to raise_error(ArgumentError, /Invalid search type/)
      end

      it "validates query is not empty" do
        expect {
          query_processor.process_query("")
        }.to raise_error(ArgumentError, /Query text cannot be nil/)
      end

      it "validates question is not empty for response generation" do
        search_results = { results: [] }

        expect {
          query_processor.generate_response("", search_results)
        }.to raise_error(ArgumentError, /Question cannot be nil/)
      end
    end

    describe "response quality" do
      it "generates coherent, well-structured responses" do
        question = "What is the relationship between AI and machine learning?"
        search_results = query_processor.process_query(question, search_type: :hybrid)

        response = query_processor.generate_response(question, search_results)

        # Check response structure
        expect(response).to have_key(:answer)
        expect(response[:answer].length).to be > 50  # Should be substantive
        expect(response[:confidence]).to be > 0.7    # Should be confident

        # Answer should be relevant to the question
        answer_lower = response[:answer].downcase
        expect(answer_lower).to match(/ai|artificial intelligence/)
        expect(answer_lower).to match(/machine learning/)
      end

      it "maintains context when generating responses" do
        # Create related sections to test context retention
        related_section = document.add_section(
          content: "Deep learning, a type of machine learning, uses neural networks with multiple layers to process complex data patterns.",
          section_title: "Deep Learning Connection",
          section_number: 3
        )
        create_test_embedding(related_section, query_similar: true)

        question = "How does deep learning relate to machine learning?"
        search_results = query_processor.process_query(question, search_type: :hybrid)

        response = query_processor.generate_response(question, search_results)

        answer_lower = response[:answer].downcase
        expect(answer_lower).to match(/deep learning/)
        expect(answer_lower).to match(/machine learning/)
        expect(answer_lower).to match(/neural networks|layers/)
      end
    end
  end

  # Helper method to create test embeddings
  def create_test_embedding(section, query_similar: false)
    # Generate vector similar to typical query vector if query_similar is true
    vector = if query_similar
               Array.new(1024) { |i| Math.sin(i * 0.01) * 0.5 }
             else
               # Generate very different vector
               Array.new(1024) { |i| Math.cos(i * 0.02) * 0.3 }
             end

    vector_str = "[#{vector.join(',')}]"
    SmartRAG::Models::Embedding.create!(
      source_id: section.id,
      vector: vector_str
    )
  end
end
