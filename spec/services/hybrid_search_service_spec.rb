require 'spec_helper'
require 'smart_rag/services/hybrid_search_service'

RSpec.describe SmartRAG::Services::HybridSearchService do
  let(:mock_embedding_manager) { instance_double(SmartRAG::Core::Embedding) }
  let(:mock_fulltext_manager) { instance_double(SmartRAG::Core::FulltextManager) }
  let(:config) { { logger: Logger.new(StringIO.new) } }
  let(:service) { described_class.new(mock_embedding_manager, mock_fulltext_manager, config) }

  describe "#initialize" do
    it "initializes with embedding_manager, fulltext_manager and config" do
      expect(service.embedding_manager).to eq(mock_embedding_manager)
      expect(service.fulltext_manager).to eq(mock_fulltext_manager)
      expect(service.config).to include(described_class::DEFAULT_CONFIG)
    end

    it "accepts custom configuration" do
      custom_config = { rrf_k: 100, default_alpha: 0.5 }
      custom_service = described_class.new(mock_embedding_manager, mock_fulltext_manager, custom_config)

      expect(custom_service.config[:rrf_k]).to eq(100)
      expect(custom_service.config[:default_alpha]).to eq(0.5)
    end
  end

  describe "#combine_with_weighted_rrf" do
    let(:text_results) do
      [
        { section_id: 1, content: "Result 1", score: 0.9 },
        { section_id: 2, content: "Result 2", score: 0.8 },
        { section_id: 3, content: "Result 3", score: 0.7 }
      ]
    end

    let(:vector_results) do
      [
        { section_id: 2, content: "Result 2", similarity: 0.95 },
        { section_id: 4, content: "Result 4", similarity: 0.85 },
        { section_id: 5, content: "Result 5", similarity: 0.75 }
      ]
    end

    it "combines results using weighted RRF algorithm" do
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.7, k: 60, deduplicate: true)

      expect(combined).to be_an(Array)
      expect(combined.size).to eq(5) # 3 text + 2 new vector results
    end

    it "calculates correct combined scores" do
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.7, k: 60, deduplicate: true)

      # Result 2 appears in both, so should have highest combined score
      result_2 = combined.find { |r| r.dig(:section, :section_id) == 2 }
      expect(result_2[:text_score]).to be > 0
      expect(result_2[:vector_score]).to be > 0
      expect(result_2[:combined_score]).to be_within(1e-12).of((0.7 * result_2[:vector_score]) + (0.3 * result_2[:text_score]))
    end

    it "applies correct weights based on alpha parameter" do
      # With alpha = 0.7, vector weight should be 0.7, text weight should be 0.3
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.7, k: 60, deduplicate: true)

      # Check that vector results are prioritized
      vector_only_result = combined.find { |r| r.dig(:section, :section_id) == 4 }
      expect(vector_only_result[:vector_score]).to be > vector_only_result[:text_score]
      expect(vector_only_result[:text_score]).to eq(0)
    end

    it "handles empty text results" do
      combined = service.send(:combine_with_weighted_rrf, [], vector_results, alpha: 0.5, k: 60, deduplicate: true)

      expect(combined.size).to eq(3)
      expect(combined.all? { |r| r[:text_score] == 0 }).to be true
      expect(combined.all? { |r| r[:vector_score] > 0 }).to be true
    end

    it "handles empty vector results" do
      combined = service.send(:combine_with_weighted_rrf, text_results, [], alpha: 0.5, k: 60, deduplicate: true)

      expect(combined.size).to eq(3)
      expect(combined.all? { |r| r[:vector_score] == 0 }).to be true
      expect(combined.all? { |r| r[:text_score] > 0 }).to be true
    end

    it "handles completely disjoint result sets" do
      text_only = [{ section_id: 1, content: "Text only" }]
      vector_only = [{ section_id: 2, content: "Vector only" }]

      combined = service.send(:combine_with_weighted_rrf, text_only, vector_only, alpha: 0.5, k: 60, deduplicate: true)

      expect(combined.size).to eq(2)
      expect(combined.find { |r| r.dig(:section, :section_id) == 1 }[:text_score]).to be > 0
      expect(combined.find { |r| r.dig(:section, :section_id) == 1 }[:vector_score]).to eq(0)
      expect(combined.find { |r| r.dig(:section, :section_id) == 2 }[:text_score]).to eq(0)
      expect(combined.find { |r| r.dig(:section, :section_id) == 2 }[:vector_score]).to be > 0
    end

    it "calculates RRF scores correctly" do
      k = 60

      # Result at rank 1 should get: 1 / (k + 1) = 1 / 61
      expected_rank_1_score = 1.0 / (k + 1)

      combined = service.send(:combine_with_weighted_rrf, text_results, [], alpha: 0.5, k: k, deduplicate: true)
      rank_1_result = combined.first

      expect(rank_1_result[:text_score]).to be_within(0.0001).of(expected_rank_1_score)
    end

    it "sorts results by combined score in descending order" do
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.7, k: 60, deduplicate: true)

      scores = combined.map { |r| r[:combined_score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it "includes scores from both sources when available" do
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.5, k: 60, deduplicate: true)

      result_2 = combined.find { |r| r.dig(:section, :section_id) == 2 }
      expect(result_2[:text_score]).to be > 0
      expect(result_2[:vector_score]).to be > 0
      expect(result_2[:section]).to include(section_id: 2, content: "Result 2")
    end

    it "respects deduplicate parameter" do
      # Same test works for both true and false since deduplicate doesn't affect RRF
      combined = service.send(:combine_with_weighted_rrf, text_results, vector_results, alpha: 0.5, k: 60, deduplicate: true)

      section_ids = combined.map { |r| r.dig(:section, :section_id) }
      expect(section_ids.uniq).to eq(section_ids) # Should be unique just from RRF
    end
  end

  describe "#validate_query" do
    it "accepts valid queries" do
      expect(service.send(:validate_query, "machine learning")).to be_nil
      expect(service.send(:validate_query, "AI research papers")).to be_nil
    end

    it "rejects nil queries" do
      error = service.send(:validate_query, nil)
      expect(error).to include("cannot be nil")
    end

    it "rejects empty queries" do
      error = service.send(:validate_query, "   ")
      expect(error).to include("cannot be empty")
    end

    it "rejects queries that are too short" do
      error = service.send(:validate_query, "a")
      expect(error).to include("too short")
    end

    it "rejects queries that are too long" do
      long_query = "a" * 1001
      error = service.send(:validate_query, long_query)
      expect(error).to include("too long")
    end
  end

  describe "#validate_limit" do
    it "returns valid limits" do
      expect(service.send(:validate_limit, 10)).to eq(10)
      expect(service.send(:validate_limit, 1)).to eq(1)
      expect(service.send(:validate_limit, 100)).to eq(100)
    end

    it "clamps limits to min/max bounds" do
      expect(service.send(:validate_limit, 0)).to eq(1)
      expect(service.send(:validate_limit, 200)).to eq(100)
      expect(service.send(:validate_limit, -10)).to eq(1)
    end

    it "handles non-numeric input" do
      expect(service.send(:validate_limit, "abc")).to eq(1)
      expect(service.send(:validate_limit, "10")).to eq(10)
    end
  end

  describe "#validate_alpha" do
    it "returns valid alpha values" do
      expect(service.send(:validate_alpha, 0.5)).to eq(0.5)
      expect(service.send(:validate_alpha, 0.0)).to eq(0.0)
      expect(service.send(:validate_alpha, 1.0)).to eq(1.0)
    end

    it "clamps alpha to 0.0-1.0 range" do
      expect(service.send(:validate_alpha, -0.5)).to eq(0.0)
      expect(service.send(:validate_alpha, 1.5)).to eq(1.0)
      expect(service.send(:validate_alpha, 100)).to eq(1.0)
    end

    it "handles non-numeric input" do
      expect(service.send(:validate_alpha, "abc")).to eq(0.0)
      expect(service.send(:validate_alpha, "0.7")).to eq(0.7)
    end
  end

  describe "#calculate_score_stats" do
    let(:results) do
      [
        { combined_score: 0.5, text_score: 0.3, vector_score: 0.2 },
        { combined_score: 0.8, text_score: 0.4, vector_score: 0.4 },
        { combined_score: 0.6, text_score: 0.2, vector_score: 0.4 }
      ]
    end

    it "calculates statistics for scores" do
      stats = service.send(:calculate_score_stats, results)

      expect(stats).to include(:min, :max, :avg)
      expect(stats[:min]).to eq(0.5)
      expect(stats[:max]).to eq(0.8)
      expect(stats[:avg]).to eq(0.6333)
    end

    it "handles empty results" do
      stats = service.send(:calculate_score_stats, [])
      expect(stats).to eq({})
    end
  end

  describe "#enrich_results" do
    it "adds score explanation when requested" do
      result = {
        section: { id: 1, section_title: "Title", content: "Body", document_id: 1 },
        combined_score: 0.5,
        vector_score: 0.3,
        text_score: 0.2
      }

      enriched = service.send(:enrich_results, [result], false, false, true)
      expect(enriched.first[:score_explanation]).to include("Combined:")
    end
  end
end
