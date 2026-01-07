require_relative "../services/embedding_service"
require_relative "../models/embedding"
require_relative "../models/source_section"
require_relative "../errors"

module SmartRAG
  module Core
    # Core embedding management class for the SmartRAG library
    class Embedding
      attr_reader :embedding_service, :config

      # Initialize the embedding manager
      # @param config [Hash] Configuration options
      def initialize(config = {})
        @embedding_service = Services::EmbeddingService.new(config)
        @config = config
        @logger = config[:logger] || Logger.new(STDOUT)
      end

      # Generate embeddings for a document
      # @param document [SourceDocument] The document to process
      # @param options [Hash] Options for processing
      # @return [Integer] Number of embeddings generated
      def generate_for_document(document, options = {})
        raise ArgumentError, "Document cannot be nil" unless document

        @logger.info "Generating embeddings for document: #{document.title}"

        sections = Models::SourceSection.where(document_id: document.id).all
        return 0 if sections.empty?

        embeddings = @embedding_service.batch_generate(sections, options)
        embeddings.size
      rescue StandardError => e
        document_id = document.respond_to?(:id) ? document.id : "unknown"
        @logger.error "Failed to generate embeddings for document #{document_id}: #{e.message}"
        raise
      end

      # Generate embeddings for multiple documents
      # @param documents [Array<SourceDocument>] Documents to process
      # @param options [Hash] Options
      # @return [Hash] Results with success/failure counts
      def batch_generate_for_documents(documents, options = {})
        results = { success: 0, failed: 0, errors: [] }

        documents.each do |document|
          count = generate_for_document(document, options)
          results[:success] += 1
          @logger.info "Generated #{count} embeddings for document #{document.id}"
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << { document_id: document.id, error: e.message }
          @logger.error "Failed to process document #{document.id}: #{e.message}"
        end

        results
      end

      # Search for similar content
      # @param query [String] Query text
      # @param options [Hash] Search options
      # @option options [Integer] :limit Maximum results (default: 10)
      # @option options [Float] :threshold Similarity threshold (default: 0.8)
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [Array<Integer>] :tag_ids Filter by tag IDs
      # @option options [String] :model Filter by model
      # @return [Array<Hash>] Results with embedding and similarity score
      def search_similar(query, options = {})
        raise ArgumentError, "Query cannot be nil or empty" if query.to_s.strip.empty?

        # Generate embedding for query
        query_embedding = generate_query_embedding(query, options)

        # Search by vector similarity
        search_by_vector(query_embedding, options)
      rescue ArgumentError
        raise
      rescue StandardError => e
        logger.error "Vector search failed: #{e.message}"
        raise ::SmartRAG::Errors::VectorSearchError, "Search failed: #{e.message}"
      end

      # Get embedding stats for a document
      # @param document [SourceDocument] Document
      # @return [Hash] Statistics
      def document_stats(document)
        raise ArgumentError, "Document cannot be nil" unless document

        section_ids = Models::SourceSection.where(document_id: document.id).map(:id)

        if section_ids.empty?
          return {
                   document_id: document.id,
                   total_sections: 0,
                   embedded_sections: 0,
                   embedding_rate: 0.0,
                   models_used: [],
                 }
        end

        embeddings = Models::Embedding.where(source_id: section_ids).all
        models = embeddings.map(&:model).uniq.compact

        {
          document_id: document.id,
          total_sections: section_ids.size,
          embedded_sections: embeddings.size,
          embedding_rate: (embeddings.size.to_f / section_ids.size * 100).round(2),
          models_used: models,
          latest_embedding: embeddings.max_by(&:created_at)&.created_at,
        }
      rescue StandardError => e
        @logger.error "Failed to get stats for document #{document.id}: #{e.message}"
        raise
      end

      # Clean up embeddings for deleted sections
      # @return [Integer] Number of cleaned embeddings
      def cleanup_orphaned_embeddings
        all_section_ids = Models::SourceSection.map(:id)
        embeddings_to_delete = Models::Embedding.exclude(source_id: all_section_ids)

        deleted_count = embeddings_to_delete.delete
        @logger.info "Cleaned up #{deleted_count} orphaned embeddings"

        deleted_count
      rescue StandardError => e
        @logger.error "Cleanup failed: #{e.message}"
        raise
      end

      # Delete old embeddings
      # @param days [Integer] Delete embeddings older than X days
      # @return [Integer] Number of deleted embeddings
      def delete_old_embeddings(days = 30)
        deleted_count = Models::Embedding.delete_old_embeddings(days: days)
        @logger.info "Deleted #{deleted_count} embeddings older than #{days} days"

        deleted_count
      rescue StandardError => e
        @logger.error "Failed to delete old embeddings: #{e.message}"
        raise
      end

      # Search similar by vector directly
      # @param vector [Array<Float>] Query vector
      # @param options [Hash] Search options
      # @return [Array<Hash>] Results
      def search_by_vector(vector, options = {})
        raise ArgumentError, "Vector cannot be nil" if vector.nil?
        raise ArgumentError, "Vector must be an array" unless vector.is_a?(Array)

        limit = options[:limit] || 10
        threshold = options[:threshold] || 0.3
        fallback_threshold = options[:fallback_threshold] || 0.1

        puts "[DEBUG] search_by_vector: vector.length=#{vector.length}, threshold=#{threshold}"

        results = Models::Embedding.similar_to(vector, limit: limit, threshold: threshold)

        if results.empty? && fallback_threshold < threshold
          logger.info "No results at threshold=#{threshold}, retrying with fallback_threshold=#{fallback_threshold}"
          results = Models::Embedding.similar_to(vector, limit: limit, threshold: fallback_threshold)
        end

        if results.empty? && options.fetch(:fallback_to_nearest, true)
          logger.info "No results after threshold fallback, returning nearest neighbors without threshold"
          results = Models::Embedding.nearest_to(vector, limit: limit)
        end

        puts "[DEBUG] search_by_vector: returned #{results.size} results"

        # Apply filters
        results = apply_filters(results, options)

        results.map.with_index do |embedding, index|
          {
            embedding: embedding,
            section: embedding.section,
            similarity: calculate_similarity(vector, embedding),
            rank: index + 1,
          }
        end
      rescue ArgumentError => e
        # Re-raise validation errors
        raise e
      rescue StandardError => e
        logger.error "Vector search failed: #{e.message}"
        raise
      end

      # Search similar by vector with tag-based filtering
      # @param vector [Array<Float>] Query vector
      # @param tags [Array<Tag, Integer, String>] Tags to filter by
      # @param options [Hash] Search options
      # @option options [Integer] :limit Maximum results (default: 10)
      # @option options [Float] :threshold Similarity threshold (default: 0.3)
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [String] :model Filter by model
      # @option options [Float] :tag_boost_weight Boost factor for matching tags (default: 1.1)
      # @return [Array<Hash>] Results with boosted scores
      def search_by_vector_with_tags(vector, tags, options = {})
        raise ArgumentError, "Vector cannot be nil" if vector.nil?
        raise ArgumentError, "Vector must be an array" unless vector.is_a?(Array)
        raise ArgumentError, "Tags cannot be nil" if tags.nil?

        limit = options[:limit] || 10
        threshold = options[:threshold] || 0.3
        tag_boost_weight = options[:tag_boost_weight] || 1.1

        # Get base results
        results = search_by_vector(vector, options)

        # Boost results that match tags
        results_with_boosts = results.map do |result|
          boosted_score = result[:similarity]

          if tags.any?
            # Check if section has matching tags
            section_id = result[:section].id
            section_tags = Models::SectionTag.where(section_id: section_id).map(&:tag_id)

            tag_ids = tags.map do |tag|
              case tag
              when ::SmartRAG::Models::Tag
                tag.id
              when Integer
                tag
              when String
                tag_obj = ::SmartRAG::Models::Tag.find(name: tag)
                tag_obj&.id
              end
            end.compact

            # Boost if any tag matches
            if (tag_ids & section_tags).any?
              boosted_score = result[:similarity] * tag_boost_weight
            end
          end

          result.merge(boosted_score: boosted_score)
        end

        # Sort by boosted score and limit
        final_limit = options[:limit] || limit
        results_with_scores = results_with_boosts.sort_by { |r| -r[:boosted_score] }

        filtered_results = results_with_scores.select { |r| r[:boosted_score] >= threshold }
        final_results = filtered_results.first(final_limit)

        logger.info "Tag-enhanced search returned #{final_results.size} results (tag boost: #{tag_boost_weight})"

        final_results
      rescue ArgumentError => e
        # Re-raise validation errors
        raise e
      rescue StandardError => e
        logger.error "Vector search failed: #{e.message}"
        raise
      end

      private

      attr_reader :logger, :config

      def generate_query_embedding(query, options = {})
        @embedding_service.send(:generate_embedding, query, options)
      end

      def ensure_tag_objects(tags)
        tags.map do |tag|
          case tag
          when ::SmartRAG::Models::Tag
            tag
          when Integer
            ::SmartRAG::Models::Tag.find(id: tag) || raise(ArgumentError, "Tag not found: #{tag}")
          when String
            ::SmartRAG::Models::Tag.find(name: tag) || raise(ArgumentError, "Tag not found: #{tag}")
          else
            raise ArgumentError, "Invalid tag type: #{tag.class}"
          end
        end
      end

      def apply_filters(results, options)
        # Filter by document IDs
        if options[:document_ids]
          document_section_ids = Models::SourceSection.where(
            document_id: options[:document_ids],
          ).map(:id)

          results = results.select do |emb|
            document_section_ids.include?(emb.is_a?(Hash) ? emb[:embedding].source_id : emb.source_id)
          end
        end

        # Filter by tag IDs
        if options[:tag_ids]
          section_tag_ids = Models::SectionTag.where(
            tag_id: options[:tag_ids],
          ).map(:section_id)

          results = results.select do |emb|
            section_tag_ids.include?(emb.is_a?(Hash) ? emb[:embedding].source_id : emb.source_id)
          end
        end

        # Filter by model
        if options[:model]
          results = results.select { |emb| (emb.is_a?(Hash) ? emb[:embedding].model : emb.model) == options[:model] }
        end

        results
      end

      def calculate_similarity(query_vector, embedding)
        # Use pgvector distance if available
        return embedding.similarity_to(query_vector) if embedding.respond_to?(:similarity_to)

        # Fallback to manual calculation
        cosine_similarity(query_vector, embedding.vector_array)
      end

      def cosine_similarity(v1, v2)
        return 0.0 if v1.nil? || v2.nil? || v1.empty? || v2.empty?

        dot_product = v1.zip(v2).map { |a, b| a * b }.sum
        magnitude1 = Math.sqrt(v1.map { |x| x * x }.sum)
        magnitude2 = Math.sqrt(v2.map { |x| x * x }.sum)
        return 0.0 if magnitude1 == 0 || magnitude2 == 0

        dot_product / (magnitude1 * magnitude2)
      end
    end
  end
end
