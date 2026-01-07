require "spec_helper"
require "smart_rag/core/embedding"

RSpec.describe SmartRAG::Core::Embedding do
  let(:mock_llm_client) { instance_double("LLMClient") }
  let(:mock_embedding_service) { instance_double("SmartRAG::Services::EmbeddingService") }
  let(:embedding_manager) { described_class.new({}) }

  let(:document) do
    instance_double(
      "SmartRAG::Models::SourceDocument",
      id: 1,
      title: "Test Document"
    )
  end

  let(:section) do
    instance_double(
      "SmartRAG::Models::SourceSection",
      id: 10,
      section_title: "Test Section",
      content: "Test content",
      document_id: 1
    )
  end

  let(:embedding) do
    instance_double(
      "SmartRAG::Models::Embedding",
      id: 100,
      source_id: 10,
      created_at: Time.now
    )
  end

  let(:vector) { Array.new(1024) { rand(0.0..1.0) } }

  before do
    allow(SmartRAG::Services::EmbeddingService).to receive(:new).and_return(mock_embedding_service)
    allow(mock_embedding_service).to receive(:batch_generate).and_return([embedding])
    allow(mock_embedding_service).to receive(:send).and_return(vector)
  end

  describe "#generate_for_document" do
    it "generates embeddings for all sections in a document" do
      allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(all: [section]))

      count = embedding_manager.generate_for_document(document)

      expect(count).to eq(1)
      expect(mock_embedding_service).to have_received(:batch_generate).with([section], {})
    end

    it "returns 0 for documents without sections" do
      allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(all: []))

      count = embedding_manager.generate_for_document(document)

      expect(count).to eq(0)
    end

    it "raises error for nil document" do
      expect { embedding_manager.generate_for_document(nil) }.to raise_error(ArgumentError, "Document cannot be nil")
    end
  end

  describe "#batch_generate_for_documents" do
    let(:document1) { instance_double("SmartRAG::Models::SourceDocument", id: 1, title: "Doc 1") }
    let(:document2) { instance_double("SmartRAG::Models::SourceDocument", id: 2, title: "Doc 2") }

    it "processes multiple documents" do
      allow(embedding_manager).to receive(:generate_for_document).and_return(2, 3)

      results = embedding_manager.batch_generate_for_documents([document1, document2])

      expect(results[:success]).to eq(2)
      expect(results[:failed]).to eq(0)
      expect(results[:errors]).to be_empty
    end

    it "continues processing on failures" do
      allow(embedding_manager).to receive(:generate_for_document).and_raise(StandardError.new("Failed"))

      results = embedding_manager.batch_generate_for_documents([document1])

      expect(results[:success]).to eq(0)
      expect(results[:failed]).to eq(1)
      expect(results[:errors]).not_to be_empty
    end
  end

  describe "#search_similar" do
    let(:search_result) do
      {
        embedding: embedding,
        section: section,
        similarity: 0.85,
        rank: 1
      }
    end

    before do
    end

    it "searches for similar content" do
      allow(mock_embedding_service).to receive(:send).and_return(vector)
      allow(SmartRAG::Models::Embedding).to receive(:similar_to).and_return([embedding])
      allow(embedding).to receive(:section).and_return(section)
      allow(embedding).to receive(:vector_array).and_return(vector)
      allow(section).to receive(:id).and_return(10)

      results = embedding_manager.search_similar("test query")

      expect(results).not_to be_empty
      expect(results.first[:similarity]).to be_within(0.0001).of(1.0)
    end

    it "raises error for empty query" do
      expect { embedding_manager.search_similar("") }.to raise_error(ArgumentError, "Query cannot be nil or empty")
    end

    it "applies document filter" do
      allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(map: [10]))

      results = embedding_manager.search_similar("test", document_ids: [1])

      expect(SmartRAG::Models::SourceSection).to have_received(:where).with(document_id: [1])
    end

    it "applies tag filter" do
      allow(SmartRAG::Models::SectionTag).to receive(:where).and_return(double(map: [10]))

      results = embedding_manager.search_similar("test", tag_ids: [1, 2])

      expect(SmartRAG::Models::SectionTag).to have_received(:where).with(tag_id: [1, 2])
    end
  end

  describe "#search_by_vector" do
    let(:search_result) do
      {
        embedding: embedding,
        section: section,
        similarity: 0.90,
        rank: 1
      }
    end

    before do
      allow(SmartRAG::Models::Embedding).to receive(:similar_to).and_return([embedding])
      allow(embedding).to receive(:section).and_return(section)
      allow(embedding).to receive(:vector_array).and_return(Array.new(1024) { |i| i < 512 ? 0.9 : 0.1 })
    end

    it "searches by vector" do
      results = embedding_manager.search_by_vector(vector, limit: 5, threshold: 0.8)

      expect(results).not_to be_empty
      expect(results.first[:similarity]).to be_within(0.02).of(0.68)
    end

    it "validates vector format" do
      expect { embedding_manager.search_by_vector("not array") }.to raise_error(ArgumentError, "Vector must be an array")
      expect { embedding_manager.search_by_vector(nil) }.to raise_error(ArgumentError, "Vector cannot be nil")
    end
  end

  describe "#document_stats" do
    it "returns embedding statistics for a document" do
      allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(map: [10, 20]))
      allow(SmartRAG::Models::Embedding).to receive(:where).and_return(double(all: [embedding, embedding]))
      allow(embedding).to receive(:model).and_return("text-embedding-ada-002")

      stats = embedding_manager.document_stats(document)

      expect(stats[:document_id]).to eq(1)
      expect(stats[:total_sections]).to eq(2)
      expect(stats[:embedded_sections]).to eq(2)
      expect(stats[:embedding_rate]).to eq(100.0)
      expect(stats[:models_used]).to include("text-embedding-ada-002")
    end

    it "handles document without sections" do
      allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(map: []))

      stats = embedding_manager.document_stats(document)

      expect(stats[:total_sections]).to eq(0)
      expect(stats[:embedding_rate]).to eq(0.0)
    end
  end

  describe "#cleanup_orphaned_embeddings" do
    it "removes embeddings for deleted sections" do
      allow(SmartRAG::Models::SourceSection).to receive(:map).and_return([10])
      allow(SmartRAG::Models::Embedding).to receive(:exclude).and_return(double(delete: 5))

      deleted_count = embedding_manager.cleanup_orphaned_embeddings

      expect(deleted_count).to eq(5)
    end
  end

  describe "#delete_old_embeddings" do
    it "deletes embeddings older than specified days" do
      allow(SmartRAG::Models::Embedding).to receive(:delete_old_embeddings).and_return(10)

      deleted_count = embedding_manager.delete_old_embeddings(30)

      expect(deleted_count).to eq(10)
      expect(SmartRAG::Models::Embedding).to have_received(:delete_old_embeddings).with(days: 30)
    end
  end

  describe "private methods" do
    describe "#apply_filters" do
      let(:results) { [{ embedding: embedding, section: section }] }

      it "filters by document_ids" do
        allow(SmartRAG::Models::SourceSection).to receive(:where).and_return(double(map: [10]))

        filtered = embedding_manager.send(:apply_filters, results, document_ids: [1])

        expect(filtered).not_to be_empty
      end

      it "filters by tag_ids" do
        allow(SmartRAG::Models::SectionTag).to receive(:where).and_return(double(map: [10]))

        filtered = embedding_manager.send(:apply_filters, results, tag_ids: [1, 2])

        expect(filtered).not_to be_empty
      end

      it "filters by model" do
        allow(embedding).to receive(:model).and_return("text-embedding-ada-002")

        filtered = embedding_manager.send(:apply_filters, results, model: "text-embedding-ada-002")

        expect(filtered).not_to be_empty
      end
    end

    describe "#calculate_similarity" do
      it "uses embedding similarity when available" do
        allow(embedding).to receive(:similarity_to).and_return(0.85)

        similarity = embedding_manager.send(:calculate_similarity, vector, embedding)

        expect(similarity).to eq(0.85)
      end

      it "falls back to manual calculation" do
        allow(embedding).to receive(:respond_to?).with(:similarity_to).and_return(false)
        allow(embedding).to receive(:vector_array).and_return(vector)

        similarity = embedding_manager.send(:calculate_similarity, vector, embedding)

        expect(similarity).to be_within(0.001).of(1.0)
      end
    end

    describe "#cosine_similarity" do
      it "calculates cosine similarity correctly" do
        v1 = [1.0, 0.0, 0.0]
        v2 = [1.0, 0.0, 0.0]

        similarity = embedding_manager.send(:cosine_similarity, v1, v2)

        expect(similarity).to eq(1.0)
      end

      it "handles orthogonal vectors" do
        v1 = [1.0, 0.0, 0.0]
        v2 = [0.0, 1.0, 0.0]

        similarity = embedding_manager.send(:cosine_similarity, v1, v2)

        expect(similarity).to eq(0.0)
      end

      it "handles zero vectors" do
        v1 = [0.0, 0.0, 0.0]
        v2 = [1.0, 0.0, 0.0]

        similarity = embedding_manager.send(:cosine_similarity, v1, v2)

        expect(similarity).to eq(0.0)
      end
    end
  end
end
