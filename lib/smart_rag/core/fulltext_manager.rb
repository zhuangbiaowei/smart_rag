require_relative '../parsers/query_parser'

module SmartRAG
  module Core
    # FulltextManager handles full-text search functionality and tsvector indexes
    # Supports multi-language tokenization and language detection
    class FulltextManager
      attr_reader :db, :query_parser, :logger

      # Weights for tsvector fields (A-D, A highest)
      WEIGHTS = {
        title: 'A',
        content: 'B'
      }.freeze

      # Default search configuration
      DEFAULT_CONFIG = {
        max_results: 100,
        default_language: 'en',
        result_limits: 20
      }.freeze

      # Initialize FulltextManager
      # @param db [Sequel::Database] Database connection
      # @param options [Hash] Configuration options
      def initialize(db, options = {})
        @db = db
        @query_parser = options[:query_parser] || Parsers::QueryParser.new
        @logger = options[:logger] || Logger.new(STDOUT)
        @config = DEFAULT_CONFIG.merge(options)
      end

      # Store or update full-text index for a section
      # @param section_id [Integer] Section ID
      # @param title [String] Section title
      # @param content [String] Section content
      # @param language [String] Language code
      # @return [Boolean] Success status
      def update_fulltext_index(section_id, title, content, language = 'en')
        raise ArgumentError, 'Section ID cannot be nil' unless section_id
        raise ArgumentError, 'Content cannot be nil' unless content

        # Get text search configuration for language
        config = get_text_search_config(language)

        # Prepare tsvector values
        ts_title = if title.to_s.strip.empty?
                     ''
                   else
                     setweight(
                       to_tsvector(config, title),
                       WEIGHTS[:title]
                     )
                   end

        ts_content = setweight(
          to_tsvector(config, content),
          WEIGHTS[:content]
        )

        # Combine with weights
        ts_combined = if ts_title.empty?
                        ts_content
                      else
                        # Use SQL concatenation for tsvector
                        Sequel.lit("#{ts_title} || #{ts_content}")
                      end

        # Update or insert into section_fts table
        db[:section_fts].insert_conflict(
          target: :section_id,
          update: {
            language: language,
            fts_title: ts_title,
            fts_content: ts_content,
            fts_combined: ts_combined,
            updated_at: Sequel::CURRENT_TIMESTAMP
          }
        ).insert(
          section_id: section_id,
          language: language,
          fts_title: ts_title,
          fts_content: ts_content,
          fts_combined: ts_combined
        )

        @logger.info "Updated full-text index for section #{section_id}"
        true
      rescue Sequel::Error => e
        @logger.error "Failed to update full-text index for section #{section_id}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        false
      rescue StandardError => e
        # Re-raise ArgumentError and other programming errors
        raise e if e.is_a?(ArgumentError)

        @logger.error "Failed to update full-text index for section #{section_id}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise Errors::FulltextSearchError, e.message
      end

      # Batch update full-text indexes
      # @param sections [Array<Hash>] Array of section data
      # @return [Hash] Success/failure counts
      def batch_update_fulltext(sections)
        results = { success: 0, failed: 0, errors: [] }

        sections.each do |section|
          success = update_fulltext_index(
            section[:id],
            section[:title],
            section[:content],
            section[:language] || 'en'
          )

          if success
            results[:success] += 1
          else
            results[:failed] += 1
            results[:errors] << { section_id: section[:id], error: 'Update failed' }
          end
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << { section_id: section[:id], error: e.message }
          @logger.error "Batch update failed for section #{section[:id]}: #{e.message}"
        end

        @logger.info "Batch updated #{results[:success]} full-text indexes, #{results[:failed]} failed"
        results
      end

      # Basic full-text search
      # @param query [String] Search query text
      # @param language [String] Language code (auto-detect if nil)
      # @param limit [Integer] Maximum results
      # @param options [Hash] Additional options
      # @return [Array] Search results
      def search_by_text(query, language = nil, limit = 20, options = {})
        raise ArgumentError, 'Query cannot be nil' if query.nil?
        raise ArgumentError, 'Query cannot be empty' if query.strip.empty?

        # Detect language if not provided
        language ||= detect_language_from_query(query)

        # Build tsquery
        tsquery = build_tsquery(query, language)

        # Check if db is valid and table exists before querying
        return [] if db.nil? || !db.respond_to?(:table_exists?) || !db.table_exists?(:section_fts)

        # Base dataset
        dataset = db[:section_fts]
                  .select(
                    Sequel[:section_fts][:section_id],
                    Sequel[:section_fts][:language],
                    Sequel[:source_sections][:section_title],
                    Sequel[:source_sections][:content],
                    Sequel[:source_sections][:document_id],
                    Sequel.function(
                      :ts_rank,
                      Sequel[:section_fts][:fts_combined],
                      Sequel.lit(tsquery)
                    ).as(:rank_score),
                    Sequel.function(
                      :ts_headline,
                      Sequel[:source_sections][:content],
                      Sequel.lit(tsquery),
                      'MaxWords=50, MinWords=15, MaxFragments=3'
                    ).as(:highlight)
                  )
                  .join(:source_sections, id: Sequel[:section_fts][:section_id])
                  .where(Sequel.lit("section_fts.fts_combined @@ #{tsquery}"))
                  .order(Sequel.desc(:rank_score))
                  .limit(limit)

        @logger.debug "Fulltext search SQL: #{dataset.sql}"
        @logger.debug "Fulltext search tsquery: #{tsquery}"

        # Apply filters if provided
        dataset = apply_search_filters(dataset, options[:filters])

        # Execute query and format results
        results = dataset.all.map do |row|
          format_search_result(row, query)
        end

        @logger.info "Full-text search returned #{results.length} results" if results.any?

        results
      rescue StandardError => e
        # Re-raise ArgumentError and other programming errors
        raise e if e.is_a?(ArgumentError)

        @logger.error "Full-text search failed: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise Errors::FulltextSearchError, "Search failed: #{e.message}"
      end

      # Full-text search with filters
      # @param query [String] Search query
      # @param filters [Hash] Filter options
      # @param options [Hash] Search options
      # @return [Array] Filtered results
      def search_with_filters(query, filters, options = {})
        options[:filters] = filters
        search_by_text(query, nil, options[:limit] || 20, options)
      end

      # Hybrid search combining text and vector search
      # @param text_query [String] Full-text query
      # @param vector_query [Array] Vector embedding
      # @param options [Hash] Search options
      # @return [Array] Combined results
      def hybrid_search(text_query, vector_query, options = {})
        raise ArgumentError, 'Text query or vector query must be provided' if text_query.nil? && vector_query.nil?

        limit = options[:limit] || 20
        k = options[:rrf_k] || 60 # RRF fusion parameter

        # Get results from both search methods
        text_results = text_query ? search_by_text(text_query, nil, limit * 2) : []

        # Vector search would be called here in real implementation
        # For now, we'll simulate or call a provided block
        vector_results = []
        vector_results = yield(vector_query, limit * 2) if block_given?

        # Combine results using RRF (Reciprocal Rank Fusion)
        combined = combine_results_with_rrf(text_results, vector_results, k: k)

        # Limit final results
        combined.first(limit)
      rescue StandardError => e
        @logger.error "Hybrid search failed: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise Errors::HybridSearchError, "Hybrid search failed: #{e.message}"
      end

      # Detect language for given text
      # @param text [String] Text to analyze
      # @return [String] Language code
      def detect_language(text)
        @query_parser.detect_language(text)
      end

      # Build tsquery for given text and language
      # @param text [String] Search text
      # @param language [String] Language code
      # @return [String] tsquery string
      def build_tsquery(text, language)
        @logger.debug "FulltextManager.build_tsquery called with text='#{text}', language='#{language}' (class: #{language.class})"
        @query_parser.build_tsquery(text, language)
      end

      # Parse advanced query
      # @param text [String] Query text
      # @return [Hash] Parsed query structure
      def parse_advanced_query(text)
        @query_parser.parse_advanced_query(text)
      end

      # Get search statistics
      # @return [Hash] Statistics
      def stats
        {
          total_indexed: db[:section_fts].count,
          languages: db[:section_fts].select(:language).distinct.map(:language),
          last_updated: db[:section_fts].select { max(:updated_at) }.first.values.first
        }
      rescue StandardError => e
        @logger.error "Failed to get stats: #{e.message}"
        {}
      end

      # Remove full-text index for a section
      # @param section_id [Integer] Section ID
      # @return [Boolean] Success status
      def remove_index(section_id)
        raise ArgumentError, 'Section ID cannot be nil' unless section_id

        deleted = db[:section_fts].where(section_id: section_id).delete

        if deleted > 0
          @logger.info "Removed full-text index for section #{section_id}"
          true
        else
          @logger.warn "No full-text index found for section #{section_id}"
          false
        end
      rescue Sequel::Error => e
        @logger.error "Failed to remove index for section #{section_id}: #{e.message}"
        false
      rescue StandardError => e
        # Re-raise ArgumentError and other programming errors
        raise e if e.is_a?(ArgumentError)

        @logger.error "Failed to remove index for section #{section_id}: #{e.message}"
        false
      end

      # Clean up orphaned indexes
      # @return [Integer] Number of cleaned indexes
      def cleanup_orphaned_indexes
        # Delete rows from section_fts that don't have corresponding source_sections
        count = db[:section_fts]
                .where(
                  Sequel[:section_fts][:section_id] => db[:source_sections].select(:id)
                )
                .invert # This negates the WHERE, giving us NOT IN behavior
                .or(section_id: nil) # Also clean up NULL section_id rows
                .delete

        @logger.info "Cleaned up #{count} orphaned full-text indexes"
        count
      rescue StandardError => e
        @logger.error "Failed to cleanup orphaned indexes: #{e.message}"
        0
      end

      private

      # Detect language from query (simplified implementation)
      def detect_language_from_query(query)
        @query_parser.detect_language(query)
      end

      # Apply search filters to dataset
      def apply_search_filters(dataset, filters)
        return dataset unless filters && !filters.empty?

        # Filter by document IDs
        if filters[:document_ids]
          dataset = dataset.where(
            Sequel[:source_sections][:document_id] => filters[:document_ids]
          )
        end

        # Filter by tags
        if filters[:tag_ids]
          # Use INNER JOIN for better performance when filtering
          dataset = dataset
                    .join(:section_tags, section_id: Sequel[:section_fts][:section_id])
                    .where(Sequel[:section_tags][:tag_id] => filters[:tag_ids])
        end

        # Filter by date range
        dataset = dataset.where(Sequel[:source_sections][:created_at] >= filters[:date_from]) if filters[:date_from]

        dataset = dataset.where(Sequel[:source_sections][:created_at] <= filters[:date_to]) if filters[:date_to]

        dataset
      end

      # Get text search configuration
      def get_text_search_config(language)
        config = Models::TextSearchConfig.first(language_code: language.to_s)&.config_name
        return 'pg_catalog.simple' unless config

        # For development/test environments, always fall back to simple if pg_jieba is not available
        if config == 'jieba'
          begin
            # Test if pg_jieba is available in a separate transaction
            db.fetch("SELECT to_tsvector('jieba', 'test')").first
            return 'jieba'
          rescue StandardError => e
            @logger.warn "pg_jieba extension not available, falling back to simple: #{e.message}"
            return 'pg_catalog.simple'
          end
        end

        config
      rescue StandardError => e
        @logger.warn "Failed to get text search config for #{language}: #{e.message}, using simple"
        'pg_catalog.simple'
      end

      # Set weight for tsvector (helper method)
      def setweight(vector, weight)
        return '' if vector.nil? || vector.to_s.strip.empty?

        "setweight(#{vector}, '#{weight}')"
      end

      # Convert text to tsvector (helper method)
      def to_tsvector(config, text)
        "to_tsvector('#{config}', #{escape_quote(text)})"
      end

      # Escape quotes for SQL
      def escape_quote(text)
        "'#{text.gsub("'", "''")}'"
      end

      # Combine results using RRF algorithm
      def combine_results_with_rrf(text_results, vector_results, k:)
        scores = {}

        # Score text results
        text_results.each_with_index do |result, index|
          rank = index + 1
          section_id = result[:section_id]
          scores[section_id] = {
            text_score: 1.0 / (k + rank),
            vector_score: 0,
            data: result
          }
        end

        # Score vector results
        vector_results.each_with_index do |result, index|
          rank = index + 1
          section_id = result[:section_id]

          if scores[section_id]
            scores[section_id][:vector_score] = 1.0 / (k + rank)
          else
            scores[section_id] = {
              text_score: 0,
              vector_score: 1.0 / (k + rank),
              data: result
            }
          end
        end

        # Sort by combined score
        scores.values.sort_by do |score|
          -(score[:text_score] + score[:vector_score])
        end.map { |score| score[:data] }
      end

      # Format search result
      def format_search_result(row, query)
        {
          section_id: row[:section_id],
          section_title: row[:section_title],
          content: row[:content],
          document_id: row[:document_id],
          language: row[:language],
          rank_score: row[:rank_score] || 0,
          highlight: row[:highlight] || '',
          query: query
        }
      end
    end
  end
end
