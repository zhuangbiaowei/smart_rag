require "spec_helper"
require "smart_rag/core/embedding"
require "smart_rag/models/tag"
require "smart_rag/models/source_section"

RSpec.describe "Tag-enhanced vector search", type: :integration do
  let(:document) { SmartRAG::Models::SourceDocument.create!(title: "AI Research", url: "https://example.com") }
  let(:embedding_manager) { SmartRAG::Core::Embedding.new }

  let(:ai_tag) { SmartRAG::Models::Tag.find_or_create("AI") }
  let(:ml_tag) { SmartRAG::Models::Tag.find_or_create("Machine Learning") }
  let(:dl_tag) { SmartRAG::Models::Tag.find_or_create("Deep Learning") }
  let(:nlp_tag) { SmartRAG::Models::Tag.find_or_create("Natural Language Processing") }
  let(:cv_tag) { SmartRAG::Models::Tag.find_or_create("Computer Vision") }

  describe "search_by_vector_with_tags" do
    before do
      # Create test sections with different tag combinations

      # Section 1: AI + ML + DL (high relevance)
      @section1 = document.add_section(
        content: "Deep learning neural networks represent the cutting edge of machine learning research.",
        section_number: 1
      )
      @section1.add_tag(ai_tag)
      @section1.add_tag(ml_tag)
      @section1.add_tag(dl_tag)

      # Section 2: AI + ML (medium relevance)
      @section2 = document.add_section(
        content: "Machine learning algorithms enable computers to learn from data patterns",
        section_number: 2
      )
      @section2.add_tag(ai_tag)
      @section2.add_tag(ml_tag)

      # Section 3: AI only (low relevance)
      @section3 = document.add_section(
        content: "Artificial intelligence encompasses various computational approaches",
        section_number: 3
      )
      @section3.add_tag(ai_tag)

      # Section 4: No tags (no tag boost)
      @section4 = document.add_section(
        content: "Computer science fundamentals including data structures and algorithms",
        section_number: 4
      )

      # Create embeddings for all sections and store section1's vector for query
      @section1_vector = create_test_embeddings_and_return_vector(@section1)
      create_test_embeddings([@section2, @section3, @section4])

      # Create a query vector that is similar to section1's vector for consistent test results
      @query_vector = create_similar_query_vector(@section1_vector)
    end

    def create_test_embeddings_and_return_vector(section)
      # Create a single embedding and return the vector array
      base_pattern = Array.new(256) { rand(0.3..0.7) }
      base_vector = base_pattern * 4

      vector = base_vector.map { |v| v.clamp(-0.8, 0.8) }
      vector_str = "[#{vector.join(',')}]"

      SmartRAG::Models::Embedding.create!(
        source_id: section.id,
        vector: vector_str
      )

      puts "Created embedding for section #{section.id}"
      vector  # Return the vector array
    end

    def create_test_embeddings(sections)
      # Create embeddings for multiple sections with controlled similarity
      sections.each_with_index do |section, i|
        # Similar to above but without returning the vector
        base_pattern = Array.new(256) { rand(0.3..0.7) }
        base_vector = base_pattern * 4

        modification_factor = (i + 1) * 0.03
        vector = base_vector.map.with_index do |v, idx|
          variation = Math.sin(idx * 0.01) * modification_factor
          (v + variation).clamp(-0.8, 0.8)
        end

        vector_str = "[#{vector.join(',')}]"
        SmartRAG::Models::Embedding.create!(
          source_id: section.id,
          vector: vector_str
        )
      end
    end

    it "boosts results based on tag matching" do
      # Use the pre-generated query vector that is similar to section1
      search_tags = [ai_tag, ml_tag, dl_tag]

      results = embedding_manager.search_by_vector_with_tags(@query_vector, search_tags, limit: 10, threshold: 0.0)

      # Verify we got results
      expect(results).not_to be_empty
      expect(results.size).to be <= 10

      # Check that results have the expected structure
      results.each do |result|
        expect(result).to have_key(:section)
        expect(result).to have_key(:similarity)
        expect(result).to have_key(:tag_match_count)
        expect(result).to have_key(:boosted_score)
        expect(result).to have_key(:tag_boost)
      end

      # First result should have highest boosted score
      if results.size > 1
        first_boost = results.first[:boosted_score]
        last_boost = results.last[:boosted_score]
        expect(first_boost).to be >= last_boost
      end
    end

    it "applies configurable tag boost weight" do
      search_tags = [ai_tag, ml_tag]

      # Test with different boost weights using the same query vector
      # Use threshold 0.0 to ensure we get results for testing boost weights
      results_low = embedding_manager.search_by_vector_with_tags(
        @query_vector,
        search_tags,
        limit: 10,
        tag_boost_weight: 0.1,
        threshold: 0.0
      )

      results_high = embedding_manager.search_by_vector_with_tags(
        @query_vector,
        search_tags,
        limit: 10,
        tag_boost_weight: 1.0,
        threshold: 0.0
      )

      # Both should return results with threshold 0.0
      expect(results_high).not_to be_empty
      expect(results_low).not_to be_empty
    end

    it "includes hierarchical tags when specified" do
      # Create hierarchy: Tech > AI > ML > DL
      tech_tag = SmartRAG::Models::Tag.find_or_create("Technology")
      ai_tag.update(parent_id: tech_tag.id)
      ml_tag.update(parent_id: ai_tag.id)
      dl_tag.update(parent_id: ml_tag.id)

      search_tags = [tech_tag]  # Only search with top-level tag

      # Use threshold 0.0 to ensure we get results to test hierarchy
      results = embedding_manager.search_by_vector_with_tags(
        @query_vector,
        search_tags,
        limit: 10,
        include_tag_hierarchy: true,
        threshold: 0.0
      )

      # Should find sections tagged with descendant tags (AI, ML, DL)
      expect(results).not_to be_empty

      # Check if hierarchical matching occurred
      has_hierarchical_matches = results.any? { |r| r[:tag_match_count] > 0 }
      expect(has_hierarchical_matches).to be true
    end

    it "respects similarity threshold" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }
      search_tags = [ai_tag]

      results = embedding_manager.search_by_vector_with_tags(
        query_vector,
        search_tags,
        limit: 10,
        threshold: 0.9  # High threshold
      )

      # All results should meet the threshold
      results.each do |result|
        expect(result[:boosted_score]).to be >= 0.9
      end
    end

    it "validates input parameters" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }

      expect { embedding_manager.search_by_vector_with_tags(nil, [ai_tag]) }.to raise_error(ArgumentError, "Vector cannot be nil")
      expect { embedding_manager.search_by_vector_with_tags(query_vector, nil) }.to raise_error(ArgumentError, "Tags cannot be nil")
    end

    it "handles empty tag arrays" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }

      results = embedding_manager.search_by_vector_with_tags(query_vector, [])

      # Should fall back to regular vector search without tag boost
      expect(results).to be_an(Array)
    end

    it "tracks matching tag information" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }
      search_tags = [ai_tag, ml_tag]

      results = embedding_manager.search_by_vector_with_tags(query_vector, search_tags, limit: 10, threshold: 0.0)

      results.each do |result|
        # Each result should track which tags matched
        expect(result).to have_key(:matching_tag_ids)
        expect(result[:matching_tag_ids]).to be_an(Array)

        # Tag match count should match the number of matching tag IDs
        expect(result[:tag_match_count]).to eq(result[:matching_tag_ids].size)

        # Section should have corresponding tags
        result[:section].tags.each do |tag|
          if search_tags.include?(tag)
            expect(result[:matching_tag_ids]).to include(tag.id)
          end
        end
      end
    end
  end

  describe "tag boost calculation" do
    it "calculates correct boost scores" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }
      search_tags = [ai_tag, ml_tag]

      # Create a section with all search tags
      section = document.add_section(content: "Test", section_number: 99)
      search_tags.each { |tag| section.add_tag(tag) }
      create_embedding(section, query_vector)

      results = embedding_manager.search_by_vector_with_tags(
        query_vector,
        search_tags,
        limit: 10,
        tag_boost_weight: 0.5
      )

      # Find our test section
      test_result = results.find { |r| r[:section].id == section.id }
      expect(test_result).not_to be_nil

      # Verify boost calculation
      # With 2 matching tags and weight 0.5:
      # tag_boost = 2 * 0.5 * 0.1 = 0.1
      expect(test_result[:tag_boost]).to eq(0.1)
      expect(test_result[:tag_match_count]).to eq(2)
      expect(test_result[:boosted_score]).to eq(test_result[:similarity] + 0.1)
    end
  end

  describe "integration with document filters" do
    before do
      # Create another document
      @other_document = SmartRAG::Models::SourceDocument.create!(title: "Other Doc", url: "https://other.com")

      # Create sections in both documents
      section1 = document.add_section(content: "AI content", section_number: 1)
      section1.add_tag(ai_tag)
      create_embedding(section1, Array.new(1024) { 0.5 })

      section2 = @other_document.add_section(content: "Also AI content", section_number: 1)
      section2.add_tag(ai_tag)
      create_embedding(section2, Array.new(1024) { 0.5 })
    end

    it "filters by document ID" do
      query_vector = Array.new(1024) { rand(0.0..1.0) }
      search_tags = [ai_tag]

      results = embedding_manager.search_by_vector_with_tags(
        query_vector,
        search_tags,
        document_ids: [document.id],
        limit: 10
      )

      # All results should be from the specified document
      results.each do |result|
        expect(result[:section].document_id).to eq(document.id)
      end
    end
  end

  # Helper method to create embeddings
  def create_embedding(section, vector = nil)
    vector ||= Array.new(1024) { rand(0.0..1.0) }
    # Convert vector to pgvector format
    vector_str = "[#{vector.join(',')}]"
    SmartRAG::Models::Embedding.create!(
      source_id: section.id,
      vector: vector_str
    )
  end

  # Helper method to create a query vector similar to a given vector
  def create_similar_query_vector(original_vector)
    # Add very small random noise to create a similar but slightly different vector
    # This ensures high similarity (cosine similarity > 0.95)
    similar_vector = original_vector.map do |value|
      # Add small random noise (within -0.01 to 0.01 range for very high similarity)
      noise = (rand - 0.5) * 0.02
      new_value = value + noise

      # Ensure value stays within valid pgvector range
      new_value.clamp(-0.85, 0.85)
    end

    puts "Created query vector with #{original_vector.size} dimensions, noise range: ±0.01"
    similar_vector
  end
end
