require "spec_helper"
require "smart_rag/services/vector_search_service"

RSpec.describe SmartRAG::Services::VectorSearchService do
  let(:mock_embedding_manager) { instance_double("SmartRAG::Core::Embedding") }
  let(:service) { described_class.new(mock_embedding_manager) }

  let(:section) do
    instance_double(
      "SmartRAG::Models::SourceSection",
      id: 1,
      section_title: "Test Section",
      content: "Test content",
      section_number: 1,
      document_id: 10
    )
  end

  let(:document) do
    instance_double(
      "SmartRAG::Models::SourceDocument",
      id: 10,
      title: "Test Document",
      url: "http://example.com"
    )
  end

  let(:embedding) do
    instance_double(
      "SmartRAG::Models::Embedding",
      id: 100,
      source_id: 1,
    )
  end

  let(:search_result) do
    {
      embedding: embedding,
      section: section,
      similarity: 0.85,
      rank: 1
    }
  end

  let(:vector) { Array.new(1024) { rand(0.0..1.0) } }

  describe "#search" do
    before do
      allow(mock_embedding_manager).to receive(:search_similar).and_return([search_result])
    end

    it "searches by text query" do
      result = service.search("test query")

      expect(result[:query]).to eq("test query")
      expect(result[:results]).not_to be_empty
      expect(result[:total_results]).to eq(1)
      expect(mock_embedding_manager).to have_received(:search_similar)
    end

    it "searches by vector directly" do
      allow(mock_embedding_manager).to receive(:search_by_vector).and_return([search_result])

      result = service.search(vector)

      expect(result[:query]).to include("Vector")
      expect(result[:results]).not_to be_empty
      expect(mock_embedding_manager).to have_received(:search_by_vector)
    end

    it "applies limit option" do
      service.search("test", limit: 5)

      expect(mock_embedding_manager).to have_received(:search_similar).with(
        "test", hash_including(limit: 5)
      )
    end

    it "applies threshold option" do
      service.search("test", threshold: 0.9)

      expect(mock_embedding_manager).to have_received(:search_similar).with(
        "test", hash_including(threshold: 0.9)
      )
    end

    it "handles errors gracefully" do
      allow(mock_embedding_manager).to receive(:search_similar).and_raise(StandardError.new("Search failed"))

      result = service.search("test")

      expect(result[:error]).to eq("Search failed")
      expect(result[:results]).to be_empty
    end
  end

  describe "#search_by_vector" do
    before do
      allow(mock_embedding_manager).to receive(:search_by_vector).and_return([search_result])
    end

    it "searches by vector" do
      result = service.search_by_vector(vector)

      expect(result[:query]).to include("Vector")
      expect(result[:results]).not_to be_empty
      expect(mock_embedding_manager).to have_received(:search_by_vector).with(
        vector, anything
      )
    end

    it "validates vector format" do
      expect { service.search_by_vector("not an array") }.to raise_error(ArgumentError, "Vector must be an array")
      expect { service.search_by_vector(nil) }.to raise_error(ArgumentError, "Vector cannot be nil")
    end
  end

  describe "#search_with_tag_boost" do
    let(:boosted_result) do
      search_result.merge(
        boosted_similarity: 0.95,
        matching_tags: ["ruby", "testing"]
      )
    end

    before do
      allow(mock_embedding_manager).to receive(:search_similar).and_return([
        boosted_result,
        boosted_result.merge(similarity: 0.70, boosted_similarity: 0.70)
      ])
    end

    it "boosts results matching tags" do
      result = service.search_with_tag_boost("test", tag_boost: ["ruby", "testing"])

      expect(result[:boosted_tags]).to eq(["ruby", "testing"])
      expect(result[:results].first).to have_key(:similarity)
      expect(result[:results].first[:similarity]).to be > 0
    end

    it "uses custom boost factor" do
      result = service.search_with_tag_boost("test", tag_boost: ["important"], boost_factor: 1.5)

      expect(result[:boosted_tags]).to eq(["important"])
    end
  end

  describe "#knn_search" do
    before do
      allow(mock_embedding_manager).to receive(:search_by_vector).and_return([search_result])
    end

    it "performs k-nearest neighbors search" do
      result = service.knn_search(vector, 5)

      expect(result[:total_results]).to eq(1)
      expect(result[:results]).not_to be_empty
      expect(mock_embedding_manager).to have_received(:search_by_vector).with(
        vector, hash_including(limit: 5)
      )
    end

    it "defaults to 10 neighbors" do
      service.knn_search(vector)

      expect(mock_embedding_manager).to have_received(:search_by_vector).with(
        vector, hash_including(limit: 10)
      )
    end
  end

  describe "#range_search" do
    it "converts radius to threshold" do
      allow(mock_embedding_manager).to receive(:search_by_vector).and_return([search_result])

      result = service.range_search(vector, 0.2)

      expect(mock_embedding_manager).to have_received(:search_by_vector).with(
        vector, hash_including(threshold: 0.8)
      )
    end
  end

  describe "#multi_vector_search" do
    let(:vectors) do
      [
        Array.new(1024) { rand(0.0..1.0) },
        Array.new(1024) { rand(0.0..1.0) }
      ]
    end

    before do
      allow(mock_embedding_manager).to receive(:search_by_vector).and_return([search_result])
    end

    it "averages vectors by default" do
      result = service.multi_vector_search(vectors)

      expect(mock_embedding_manager).to have_received(:search_by_vector)
      expect(result[:results]).not_to be_empty
    end

    it "supports weighted combination" do
      weights = [0.7, 0.3]
      result = service.multi_vector_search(vectors, combination: "weighted", weights: weights)

      expect(mock_embedding_manager).to have_received(:search_by_vector)
      expect(result[:results]).not_to be_empty
    end

    it "raises error for unknown combination method" do
      expect {
        service.multi_vector_search(vectors, combination: "invalid")
      }.to raise_error(ArgumentError, "Unknown combination method: invalid")
    end
  end

  describe "#cross_modal_search" do
    before do
      allow(mock_embedding_manager).to receive(:search_similar).and_return([search_result])
    end

    it "delegates to search method" do
      result = service.cross_modal_search("cross modal query")

      expect(result[:query]).to eq("cross modal query")
      expect(result[:results]).not_to be_empty
      expect(mock_embedding_manager).to have_received(:search_similar)
    end
  end

  describe "private methods" do
    describe "#format_results" do
      let(:result_with_tags) do
        search_result.merge(
          tags: [
            instance_double("SmartRAG::Models::Tag", id: 1, name: "ruby"),
            instance_double("SmartRAG::Models::Tag", id: 2, name: "testing")
          ],
          document: document
        )
      end

      it "formats results with all data" do
        formatted = service.send(:format_results, [result_with_tags], include_content: true)

        expect(formatted.first[:similarity]).to eq(0.85)
        expect(formatted.first[:section][:content]).to eq("Test content")
        expect(formatted.first[:tags].size).to eq(2)
        expect(formatted.first[:document]).to include(title: "Test Document")
      end

      it "respects include_content option" do
        formatted = service.send(:format_results, [result_with_tags], include_content: false)

        # Check that section doesn't have content (OpenStruct will respond to content but it will be nil)
        section = formatted.first[:section]
        expect(section.respond_to?(:content)).to be true
        expect(section.content).to be_nil
      end

      it "respects include_tags option" do
        formatted = service.send(:format_results, [result_with_tags], include_tags: false)

        expect(formatted.first).not_to have_key(:tags)
      end
    end

    describe "#average_vectors" do
      it "averages multiple vectors" do
        vectors = [
          [1.0, 2.0, 3.0],
          [3.0, 2.0, 1.0]
        ]

        average = service.send(:average_vectors, vectors)

        expect(average).to eq([2.0, 2.0, 2.0])
      end
    end

    describe "#weighted_vectors" do
      it "combines vectors with weights" do
        vectors = [
          [1.0, 2.0, 3.0],
          [3.0, 2.0, 1.0]
        ]
        weights = [0.5, 0.5]

        weighted = service.send(:weighted_vectors, vectors, weights)

        expect(weighted).to eq([2.0, 2.0, 2.0])
      end
    end
  end
end
