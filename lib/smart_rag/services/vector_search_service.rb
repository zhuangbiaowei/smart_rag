require_relative '../models/embedding'
require_relative '../models/source_section'
require_relative '../models/source_document'
require_relative '../models/section_tag'
require_relative '../models/tag'
require 'ostruct'

module SmartRAG
  module Services
    # Advanced vector search service with filtering and ranking capabilities
    class VectorSearchService
      attr_reader :embedding_manager, :config, :logger

      # Initialize the vector search service
      # @param embedding_manager [Core::Embedding] Embedding manager instance
      # @param config [Hash] Configuration options
      def initialize(embedding_manager, config = {})
        @embedding_manager = embedding_manager
        @config = default_config.merge(config)
        @logger = @config[:logger] || Logger.new(STDOUT)
      end

      # Search for similar content with advanced features
      # @param query [String] Query text
      # @param options [Hash] Search options
      # @option options [Integer] :limit Maximum results (default: 10)
      # @option options [Float] :threshold Minimum similarity score (default: 0.7)
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [Array<Integer>] :tag_ids Filter by tag IDs
      # @option options [Array<String>] :tags Filter by tag names (hierarchical matching)
      # @option options [Array<String>] :section_types Filter by section types
      # @option options [Boolean] :include_content Include full content in results (default: true)
      # @option options [Boolean] :include_metadata Include metadata in results (default: true)
      # @option options [String] :model Filter by embedding model
      # @return [Hash] Search results with metadata
      def search(query, options = {})
        return search_by_vector(query, options) if query.is_a?(Array)

        @logger.info "Vector search: '#{query[0...100]}'"

        results = @embedding_manager.search_similar(query, options)
        results = enhance_results(results, options)

        # Format final response
        {
          query: query,
          results: format_results(results, options),
          total_results: results.size,
          took_ms: calculate_query_time
        }
      rescue StandardError => e
        @logger.error "Vector search failed: #{e.message}"
        {
          query: query,
          results: [],
          total_results: 0,
          error: e.message,
          took_ms: calculate_query_time
        }
      end

      # Search by vector directly
      # @param vector [Array<Float>] Query vector
      # @param options [Hash] Search options
      # @return [Hash] Search results
      def search_by_vector(vector, options = {})
        raise ArgumentError, 'Vector cannot be nil' if vector.nil?
        raise ArgumentError, 'Vector must be an array' unless vector.is_a?(Array)

        @logger.info "Vector search by vector (length: #{vector.length})"

        results = @embedding_manager.search_by_vector(vector, options)
        results = enhance_results(results, options)

        {
          query: "[Vector: #{vector.length} dimensions]",
          results: format_results(results, options),
          total_results: results.size,
          took_ms: calculate_query_time
        }
      rescue ArgumentError => e
        # Re-raise validation errors
        raise e
      rescue StandardError => e
        @logger.error "Vector search failed: #{e.message}"
        {
          query: '[Vector]',
          results: [],
          total_results: 0,
          error: e.message,
          took_ms: calculate_query_time
        }
      end

      # Search with tag-based relevance boosting
      # @param query [String] Query text
      # @param options [Hash] Options
      # @option options [Array<String>] :tag_boost Tags to boost relevance
      # @option options [Float] :boost_factor Boost factor for matching tags (default: 1.2)
      # @return [Hash] Ranked results
      def search_with_tag_boost(query, options = {})
        tag_boost = options[:tag_boost] || []
        boost_factor = options[:boost_factor] || 1.2

        @logger.info "Tag-boosted search with tags: #{tag_boost.join(', ')}"

        # First get base results
        results = @embedding_manager.search_similar(query, options)

        # Boost results matching tag criteria
        results = boost_by_tags(results, tag_boost, boost_factor) if tag_boost.any?

        # Re-rank by boosted similarity
        results = results.sort_by { |r| -r[:boosted_similarity] }

        {
          query: query,
          results: format_results(results, options),
          total_results: results.size,
          boosted_tags: tag_boost,
          took_ms: calculate_query_time
        }
      end

      # KNN search (k-nearest neighbors)
      # @param vector [Array<Float>] Query vector
      # @param k [Integer] Number of neighbors
      # @param options [Hash] Search options
      # @return [Hash] KNN results
      def knn_search(vector, k = 10, options = {})
        search_by_vector(vector, options.merge(limit: k))
      end

      # Range search in vector space
      # @param vector [Array<Float>] Center vector
      # @param radius [Float] Search radius (distance)
      # @param options [Hash] Search options
      # @return [Hash] Results within radius
      def range_search(vector, radius, options = {})
        # Convert radius to similarity threshold
        # cosine distance: 0 = same, 1 = opposite, 0.2 = high similarity
        threshold = 1 - radius

        options = options.merge(threshold: threshold)
        search_by_vector(vector, options)
      end

      # Multi-vector search (combine multiple vectors)
      # @param vectors [Array<Array<Float>>] Multiple vectors
      # @param options [Hash] Search options
      # @option options [String] :combination How to combine: 'average', 'weighted' (default: 'average')
      # @option options [Array<Float>] :weights Weights for weighted combination
      # @return [Hash] Combined search results
      def multi_vector_search(vectors, options = {})
        combination = options[:combination] || 'average'
        weights = options[:weights] || Array.new(vectors.size, 1.0)

        @logger.info "Multi-vector search: #{vectors.size} vectors, #{combination} combination"

        # Combine vectors
        combined_vector = case combination
                          when 'average'
                            average_vectors(vectors)
                          when 'weighted'
                            weighted_vectors(vectors, weights)
                          else
                            raise ArgumentError, "Unknown combination method: #{combination}"
                          end

        search_by_vector(combined_vector, options)
      end

      # Search cross-modal (matching different content types)
      # Currently uses same vector space, but can be extended
      # @param query [String] Query text
      # @param options [Hash] Options
      # @return [Hash] Results
      def cross_modal_search(query, options = {})
        search(query, options)
      end

      private

      def enhance_results(results, options)
        # Add tag information
        results = enrich_with_tags(results) if options[:include_tags] != false

        # Add document information
        results = enrich_with_documents(results) if options[:include_document] != false

        # Add similarity ranking
        rank_by_similarity(results)
      end

      def enrich_with_tags(results)
        section_ids = results.map { |r| r[:section].id }

        # Fetch all tag relationships for these sections
        section_tags = Models::SectionTag.where(section_id: section_ids).all
        tag_ids = section_tags.map(&:tag_id).uniq

        # Fetch tag names
        tags_by_id = Models::Tag.where(id: tag_ids).map { |t| [t.id, t] }.to_h

        # Add tags to results
        results.map do |result|
          section_id = result[:section].id
          tag_relations = section_tags.select { |st| st.section_id == section_id }
          result[:tags] = tag_relations.map { |st| tags_by_id[st.tag_id] }.compact
          result
        end
      end

      def enrich_with_documents(results)
        document_ids = results.map { |r| r[:section].document_id }.uniq
        documents_by_id = Models::SourceDocument.where(id: document_ids).map { |d| [d.id, d] }.to_h

        results.map do |result|
          doc_id = result[:section].document_id
          result[:document] = documents_by_id[doc_id]
          result
        end
      end

      def rank_by_similarity(results)
        # Already sorted by similarity from search
        results.each_with_index.map do |result, index|
          result[:rank] = index + 1
          result
        end
      end

      def boost_by_tags(results, tag_boost, boost_factor)
        section_tags_map = build_section_tags_map(results)

        results.map do |result|
          section_tags = section_tags_map[result[:section].id] || []
          matching_tags = section_tags & tag_boost

          boost = matching_tags.any? ? boost_factor : 1.0
          boosted_similarity = result[:similarity] * boost

          result.merge(
            boosted_similarity: boosted_similarity,
            matching_tags: matching_tags
          )
        end
      end

      def build_section_tags_map(results)
        section_ids = results.map { |r| r[:section].id }
        tags_by_section = Models::SectionTag.where(section_id: section_ids).all

        tags_by_section.each_with_object({}) do |st, map|
          map[st.section_id] ||= []
          map[st.section_id] << st.tag_id
        end
      end

      def format_results(results, options)
        results.map do |result|
          # Create section object that can be accessed as both hash and object
          section_data = {
            id: result[:section].id,
            title: result[:section].section_title,
            document_id: result[:section].document_id
          }

          # Include full content or set to nil
          section_data[:content] = (result[:section].content if options[:include_content] != false)

          # Wrap in OpenStruct to allow method access
          section = OpenStruct.new(section_data)

          formatted = {
            similarity: result[:similarity],
            rank: result[:rank],
            embedding: {
              id: result[:embedding].id
            },
            section: section
          }

          # Include tags
          if result[:tags] && options[:include_tags] != false
            formatted[:tags] = result[:tags].map { |t| { id: t.id, name: t.name } }
          end

          # Include document info
          if result[:document] && options[:include_document] != false
            formatted[:document] = {
              id: result[:document].id,
              title: result[:document].title,
              url: result[:document].url
            }
          end

          formatted
        end
      end

      def average_vectors(vectors)
        dimension = vectors.first.length
        sum_vector = Array.new(dimension, 0.0)

        vectors.each do |vector|
          vector.each_with_index do |value, index|
            sum_vector[index] += value
          end
        end

        sum_vector.map { |v| v / vectors.size }
      end

      def weighted_vectors(vectors, weights)
        dimension = vectors.first.length
        weighted_vector = Array.new(dimension, 0.0)
        total_weight = weights.sum

        vectors.each_with_index do |vector, vec_index|
          weight = weights[vec_index] || 1.0
          vector.each_with_index do |value, index|
            weighted_vector[index] += value * weight
          end
        end

        weighted_vector.map { |v| v / total_weight }
      end

      def calculate_query_time
        # In real implementation, you'd track actual timing
        # For now return placeholder
        0
      end

      def default_config
        {
          limit: 10,
          threshold: 0.3,
          include_content: true,
          include_metadata: true,
          logger: Logger.new(STDOUT)
        }
      end
    end
  end
end
