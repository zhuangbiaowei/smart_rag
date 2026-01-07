require_relative '../core/embedding'
require_relative '../core/fulltext_manager'
require_relative '../errors'

require 'concurrent'
require 'logger'
require 'json'

module SmartRAG
  module Services
    # HybridSearchService provides unified interface for hybrid search combining vector and full-text search
    # Uses RRF (Reciprocal Rank Fusion) algorithm to combine results
    class HybridSearchService
      attr_reader :embedding_manager, :fulltext_manager, :config, :logger

      # Default configuration for hybrid search
      DEFAULT_CONFIG = {
        # RRF parameters
        rrf_k: 60, # RRF constant (higher = more weight to lower ranks)
        default_alpha: 0.7, # Weight for vector search results (0.0-1.0)

        # Search parameters
        default_limit: 20,
        max_limit: 100,
        min_limit: 1,

        # Query parameters
        min_query_length: 2,
        max_query_length: 1000,

        # Result parameters
        deduplicate_results: true,
        include_explanations: false,

        # Vector search weight adjustments
        vector_weight_boost: 1.0,
        fulltext_weight_boost: 1.0
      }.freeze

      # Initialize HybridSearchService
      # @param embedding_manager [Core::Embedding] Vector embedding manager
      # @param fulltext_manager [Core::FulltextManager] Full-text search manager
      # @param config [Hash] Configuration options
      def initialize(embedding_manager, fulltext_manager, config = {})
        @embedding_manager = embedding_manager
        @fulltext_manager = fulltext_manager
        @config = DEFAULT_CONFIG.merge(config)
        @logger = config[:logger] || Logger.new(STDOUT)
      end

      # Perform hybrid search combining vector and full-text results
      # @param query [String] Search query text
      # @param options [Hash] Search options
      # @option options [String] :language Language code (auto-detect if nil)
      # @option options [Integer] :limit Maximum results (default: 20)
      # @option options [Float] :alpha Vector search weight (0.0-1.0, default: 0.7)
      # @option options [Integer] :rrf_k RRF constant (default: 60)
      # @option options [Hash] :filters Search filters
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [Array<Integer>] :tag_ids Filter by tag IDs
      # @option options [Array<Tag>] :tags Tags to filter by
      # @option options [Array<Float>] :query_embedding Pre-computed query embedding (optional)
      # @option options [Boolean] :include_content Include full content
      # @option options [Boolean] :include_metadata Include metadata
      # @option options [Boolean] :enable_deduplication Deduplicate results
      # @option options [Boolean] :include_explanations Include score explanations
      # @return [Hash] Search results with combined rankings
      def search(query, options = {})
        # Initialize variables for error handling
        final_results = []
        start_time = Time.now
        language = options[:language]
        alpha = config[:default_alpha]
        rrf_k = config[:rrf_k]

        begin
          # Validate query
          validation_error = validate_query(query)
          if validation_error
            @logger.error "Hybrid search validation failed: #{validation_error}"
            raise ArgumentError, validation_error
          end

          # Extract options
          language = options[:language] || detect_language(query)
          limit = validate_limit(options[:limit] || config[:default_limit])
          alpha = validate_alpha(options[:alpha] || config[:default_alpha])
          alpha = adjust_alpha_for_query(alpha, query, language)
          rrf_k = options[:rrf_k] || config[:rrf_k]
          filters = options[:filters] || {}
          deduplicate = options.fetch(:enable_deduplication, config[:deduplicate_results])
          include_content = options.fetch(:include_content, false)
          include_metadata = options.fetch(:include_metadata, true)
          include_explanations = options.fetch(:include_explanations, config[:include_explanations])
          query_embedding = options[:query_embedding]

          @logger.info "Hybrid search: '#{query}', language: #{language}, limit: #{limit}, alpha: #{alpha}"

          # Execute both search methods
          start_time = Time.now
          @logger.debug 'Starting text search...'
          text_results = perform_text_search(query, language, limit, filters)
          @logger.debug "Text search completed: #{text_results.length} results"

          @logger.debug 'Starting vector search...'
          vector_results = perform_vector_search(query, query_embedding, limit, filters)
          @logger.debug "Vector search completed: #{vector_results.length} results"

          # Combine results using weighted RRF
          combined_results = combine_with_weighted_rrf(
            text_results,
            vector_results,
            alpha: alpha,
            k: rrf_k,
            deduplicate: deduplicate
          )

          combined_results = add_category_fallback_results(combined_results, query, language)

          # Limit results
          final_results = combined_results.first(limit)

          @logger.debug "Before enrichment: final_results count=#{final_results.length}"

          # Enrich results if requested
          if include_content || include_metadata || include_explanations
            @logger.debug "Calling enrich_results with include_content=#{include_content}, include_metadata=#{include_metadata}"
            final_results = enrich_results(final_results, include_content, include_metadata, include_explanations)
            @logger.debug "After enrichment: enriched results count=#{final_results.length}"
          end

          execution_time = ((Time.now - start_time) * 1000).round

          # Build response
          response = {
            query: query,
            results: final_results,
            metadata: {
              total_count: final_results.length,
              execution_time_ms: execution_time,
              language: language,
              alpha: alpha,
              rrf_k: rrf_k,
              text_result_count: text_results.length,
              vector_result_count: vector_results.length,
              combined_score_stats: calculate_score_stats(final_results)
            }
          }

          # Log search
          log_search(query, 'hybrid', response[:results].length, execution_time)

          @logger.info "Hybrid search completed: #{final_results.length} results in #{execution_time}ms"

          response
        rescue ArgumentError => e
          # Return empty results on validation error
          execution_time = ((Time.now - start_time) * 1000).round
          {
            query: query,
            results: [],
            metadata: {
              total_count: 0,
              execution_time_ms: execution_time,
              language: language || config[:default_language],
              alpha: alpha || config[:default_alpha],
              rrf_k: rrf_k || config[:rrf_k],
              text_result_count: 0,
              vector_result_count: 0,
              combined_score_stats: {},
              error: e.message
            }
          }
        rescue StandardError => e
          @logger.error "Hybrid search failed: #{e.message}"
          @logger.error e.backtrace.join("\n")
          log_search(query, 'hybrid', 0, 0, e.message)
          # Return empty results on error instead of crashing
          # This allows tests and callers to handle errors gracefully
          execution_time = ((Time.now - start_time) * 1000).round
          {
            query: query,
            results: [],
            metadata: {
              total_count: 0,
              execution_time_ms: execution_time,
              language: language || config[:default_language],
              alpha: alpha || config[:default_alpha],
              rrf_k: rrf_k || config[:rrf_k],
              text_result_count: 0,
              vector_result_count: 0,
              combined_score_stats: {},
              error: e.message
            }
          }
        end
      end

      def validate_query(query)
        return 'Query cannot be nil' if query.nil?
        return 'Query cannot be empty' if query.strip.empty?

        length = query.strip.length
        return "Query too short (minimum #{config[:min_query_length]} characters)" if length < config[:min_query_length]

        return "Query too long (maximum #{config[:max_query_length]} characters)" if length > config[:max_query_length]

        nil
      end

      def log_search(query, search_type, result_count, execution_time, error = nil)
        # Skip logging validation errors (nil/empty queries)
        return if query.nil? || query.to_s.strip.empty?

        begin
          # Skip logging if database or fulltext_manager is not available
          return unless @fulltext_manager && @fulltext_manager.respond_to?(:db) && @fulltext_manager.db

          # Build insert hash without error_message column (not in migration)
          log_data = {
            query: query.to_s,
            search_type: search_type,
            execution_time_ms: execution_time,
            results_count: result_count,
            created_at: Sequel::CURRENT_TIMESTAMP
          }

          # Only add filters if we have error (but format differently for existing columns)
          log_data[:filters] = { error: error }.to_json if error

          @fulltext_manager.db[:search_logs].insert(log_data) if fulltext_manager.db[:search_logs]
        rescue StandardError => e
          @logger.error "Failed to log search: #{e.message}"
        end
      end

      private

      def detect_language(query)
        fulltext_manager.detect_language(query)
      end

      def validate_limit(limit)
        limit = limit.to_i
        [[config[:min_limit], limit].max, config[:max_limit]].min
      end

      def validate_alpha(alpha)
        [[0.0, alpha.to_f].max, 1.0].min
      end

      def adjust_alpha_for_query(alpha, query, language)
        return alpha unless query

        length = query.strip.length
        return alpha if length == 0

        # Favor fulltext for short queries where exact keyword match is strong.
        if language == :zh && length <= 2
          return [alpha, 0.3].min
        end

        alpha
      end

      def add_category_fallback_results(results, query, language)
        term = query.to_s.strip
        return results unless language == :zh && term.length <= 2

        category_docs = documents_with_category(term)
        return results if category_docs.empty?

        existing_doc_ids = results.map { |r| extract_document_id(r[:section]) }.compact

        category_docs.each do |doc|
          next if existing_doc_ids.include?(doc.id)

          section = ::SmartRAG::Models::SourceSection
            .where(document_id: doc.id)
            .order(:section_number)
            .first
          next unless section

          results << {
            section: section,
            combined_score: 1.0,
            vector_score: 0.0,
            text_score: 1.0
          }
        end

        results.sort_by { |r| -r[:combined_score] }
      end

      def documents_with_category(term)
        ::SmartRAG::Models::SourceDocument.all.select do |doc|
          metadata = parse_metadata(doc.metadata)
          category = metadata["category"] || metadata[:category]
          category.to_s.include?(term)
        end
      end

      def parse_metadata(raw)
        return {} if raw.nil?
        return raw if raw.is_a?(Hash)

        JSON.parse(raw)
      rescue StandardError
        {}
      end

      def extract_document_id(section)
        if section.is_a?(Hash)
          section[:document_id] || section['document_id']
        else
          section&.document_id
        end
      end

      def perform_text_search(query, language, limit, filters)
        if filters && !filters.empty?
          # Convert tags to tag_ids for fulltext manager
          search_filters = filters.dup
          if filters[:tags] && !filters[:tags].empty?
            # Convert Tag objects to IDs
            search_filters[:tag_ids] = filters[:tags].map do |tag|
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
            # Remove the original :tags key as fulltext manager expects :tag_ids
            search_filters.delete(:tags)
          end

          fulltext_manager.search_by_text(query, language, limit, filters: search_filters)
        else
          fulltext_manager.search_by_text(query, language, limit)
        end
      end

      def perform_vector_search(query, query_embedding, limit, filters)
        if query_embedding
          # Use pre-computed embedding (more efficient)
          tags = filters[:tags]
          if tags && !tags.empty?
            embedding_manager.search_by_vector_with_tags(query_embedding, tags, limit: limit)
          else
            embedding_manager.search_by_vector(query_embedding, limit: limit)
          end
        else
          # Fallback to query text (will generate embedding internally)
          embedding_manager.search_similar(query, limit: limit)
        end
      end

      def combine_with_weighted_rrf(text_results, vector_results, alpha:, k:, deduplicate:)
        # Convert text results to RRF format
        text_rrf = text_results.each_with_index.map do |result, idx|
          { result: result, section: normalize_result_section(result), score: 1.0 / (k + idx + 1), source: :text }
        end

        # Convert vector results to RRF format
        vector_rrf = vector_results.each_with_index.map do |result, idx|
          { result: result, section: normalize_result_section(result), score: 1.0 / (k + idx + 1), source: :vector }
        end

        # Group by section_id or other unique identifier
        combined = {}
        text_rrf.each do |item|
          key = extract_result_key(item[:result])
          combined[key] ||= { section: item[:section], text_score: 0, vector_score: 0 }
          combined[key][:text_score] = item[:score]
        end

        vector_rrf.each do |item|
          key = extract_result_key(item[:result])
          combined[key] ||= { section: item[:section], text_score: 0, vector_score: 0 }
          combined[key][:vector_score] = item[:score]
        end

        # Calculate weighted scores and sort
        combined.map do |_key, data|
          combined_score = alpha * data[:vector_score] + (1 - alpha) * data[:text_score]
          {
            section: data[:section],
            combined_score: combined_score,
            vector_score: data[:vector_score],
            text_score: data[:text_score]
          }
        end.sort_by { |r| -r[:combined_score] }
      end

      def normalize_result_section(result)
        return result[:section] if result.is_a?(Hash) && result[:section]

        result
      end

      def extract_result_key(result)
        # Extract a unique key for deduplication
        # For vector search results, we want document_id (not section_id)
        # because we want to dedupe by document, not by section
        case result
        when Hash
          # If result is from vector search, it has format: {embedding, section, similarity}
          # We want to use document_id for deduplication
          if result[:section]
            # section may be a Hash or a SourceSection object
            if result[:section].is_a?(Hash)
              result[:section][:document_id] || result[:section][:id] || result[:section][:section_id] || result[:id]
            else
              # SourceSection object - try to get document_id
              begin
                result[:section].document_id
              rescue StandardError
                result[:id] || result.object_id
              end
            end
          else
            # For fulltext search results or fallback
            result[:section_id] || result[:id] || result.object_id
          end
        else
          # For objects (SourceSection, etc.)
          begin
            result.document_id
          rescue StandardError
            result.id || result.object_id
          end
        end
      end

      def enrich_results(results, include_content, include_metadata, include_explanations)
        @logger.debug "enrich_results called with: include_content=#{include_content}, include_metadata=#{include_metadata}, include_explanations=#{include_explanations}"

        results.map do |result|
          enriched = result.dup
          section = result[:section]

          @logger.debug "Processing result, section class=#{section.class}, section inspect=#{section.inspect[0..200]}"

          if include_content
            enriched[:content] = if section.is_a?(Hash)
                                   section[:content] || section['content'] || ''
                                 else
                                   section&.content || ''
                                 end
          end

          if include_metadata
            document_id = if section.is_a?(Hash)
                            section[:document_id] || section['document_id']
                          else
                            section&.document_id
                          end

            @logger.debug "Document ID extracted: #{document_id.inspect} (section type: #{section.class})"

            base_metadata = if section.is_a?(Hash)
                              {
                                section_id: section[:id] || section['id'] || section[:section_id],
                                document_id: document_id
                              }
                            else
                              {
                                section_id: section&.id,
                                document_id: document_id
                              }
                            end

            if document_id && document_id != ''
              begin
                doc = @fulltext_manager.db[:source_documents].where(id: document_id).first
                @logger.debug "Fetched document for id=#{document_id}: doc=#{doc ? 'found' : 'nil'}"

                if doc
                  # Add document title
                  base_metadata[:document_title] = doc[:title] if doc[:title]

                  # Merge document metadata (may contain category, author, etc.)
                  if doc[:metadata]
                    @logger.debug "Document metadata found: #{doc[:metadata].inspect}"
                    parsed_metadata = if doc[:metadata].is_a?(String)
                                        begin
                                          JSON.parse(doc[:metadata])
                                        rescue StandardError
                                          {}
                                        end
                                      else
                                        doc[:metadata]
                                      end
                    @logger.debug "Parsed metadata: #{parsed_metadata.inspect}"
                    base_metadata.merge!(parsed_metadata) if parsed_metadata.is_a?(Hash)
                  else
                    @logger.debug 'Document has no metadata field or is nil'
                  end
                else
                  @logger.warn "Document not found for id=#{document_id}"
                end
              rescue StandardError => e
                @logger.warn "Failed to fetch document metadata for document_id=#{document_id}: #{e.message}"
                @logger.debug e.backtrace[0..5].join("\n")
              end
            else
              @logger.warn 'Document ID is nil or empty'
            end

            enriched[:metadata] = base_metadata
          end

          if include_explanations
            enriched[:score_explanation] =
              "Combined: #{result[:combined_score].round(4)} (vector: #{result[:vector_score].round(4)}, text: #{result[:text_score].round(4)})"
          end

          enriched
        end
      end

      def calculate_score_stats(results)
        return {} if results.empty?

        scores = results.map { |r| r[:combined_score] }
        {
          min: scores.min.round(4),
          max: scores.max.round(4),
          avg: (scores.sum / scores.size.to_f).round(4)
        }
      end
    end
  end
end
