require_relative '../core/fulltext_manager'

module SmartRAG
  module Services
    # FulltextSearchService executes full-text keyword search with multi-language support
    # Provides a clean interface for full-text search operations
    class FulltextSearchService
      attr_reader :fulltext_manager, :query_parser, :config, :logger

      # Default service configuration
      DEFAULT_CONFIG = {
        default_language: 'en',
        max_results: 100,
        default_limit: 20,
        enable_highlighting: true,
        highlight_options: {
          max_words: 50,
          min_words: 15,
          max_fragments: 3,
          start_sel: '<mark>',
          stop_sel: '</mark>'
        },
        enable_spellcheck: false,
        enable_suggestions: false,
        min_search_length: 2, # Minimum query length
        max_search_length: 1000 # Maximum query length
      }.freeze

      # Initialize FulltextSearchService
      # @param fulltext_manager [FulltextManager] Full-text manager instance
      # @param query_parser [QueryParser] Query parser instance
      # @param options [Hash] Service configuration options
      def initialize(fulltext_manager, query_parser = nil, options = {})
        @fulltext_manager = fulltext_manager
        @query_parser = query_parser || fulltext_manager.query_parser
        @config = DEFAULT_CONFIG.merge(options)
        @logger = options[:logger] || Logger.new(STDOUT)
      end

      # Perform full-text search
      # @param query [String] Search query text
      # @param options [Hash] Search options
      # @option options [String] :language Language code (auto-detect if nil)
      # @option options [Integer] :limit Maximum results (default: 20)
      # @option options [Boolean] :enable_highlighting Enable highlighting (default: true)
      # @option options [Hash] :filters Search filters
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [Array<Integer>] :tag_ids Filter by tag IDs
      # @option options [DateTime] :date_from Filter by start date
      # @option options [DateTime] :date_to Filter by end date
      # @option options [Boolean] :include_content Include full content in results
      # @option options [Boolean] :include_metadata Include metadata in results
      # @return [Hash] Search results with metadata
      def search(query, options = {})
        # Validate query
        validation_error = validate_query(query)
        raise ArgumentError, validation_error if validation_error

        # Parse advanced queries if needed
        query_info = analyze_query(query)

        # Extract options
        language = options[:language] || detect_language(query)
        limit = options[:limit] || config[:default_limit]
        filters = options[:filters] || extract_filters(options)

        # Log search start
        @logger.info "Full-text search: '#{query}', language: #{language}, limit: #{limit}"

        # Execute search
        start_time = Time.now
        results = if filters.empty?
                    fulltext_manager.search_by_text(query, language, limit)
                  else
                    fulltext_manager.search_with_filters(query, filters, {
                                                           language: language,
                                                           limit: limit
                                                         })
                  end
        execution_time = ((Time.now - start_time) * 1000).round

        # Format results with highlighting and metadata
        formatted_results = format_search_results(results, options)

        # Generate response
        response = {
          query: query,
          query_info: query_info,
          results: formatted_results,
          metadata: {
            total_count: results.length,
            execution_time_ms: execution_time,
            language: language,
            has_more: results.length >= limit
          }
        }

        # Add spellcheck/suggestions if enabled
        response[:suggestions] = generate_suggestions(query, language) if config[:enable_spellcheck] && results.empty?

        # Log search completion
        log_search(query, results.length, execution_time)

        response
      rescue ArgumentError => e
        # Re-raise ArgumentError (validation errors) without wrapping
        log_search(query, 0, 0, e.message)
        raise e
      rescue StandardError => e
        @logger.error "Full-text search failed: #{e.message}"
        @logger.error e.backtrace.join("\n")
        log_search(query, 0, 0, e.message)
        raise Errors::FulltextSearchServiceError, "Search failed: #{e.message}"
      end

      # Quick search without metadata
      # @param query [String] Search query
      # @param limit [Integer] Result limit
      # @return [Array] Simple result list
      def quick_search(query, limit = 10)
        results = fulltext_manager.search_by_text(query, nil, limit)
        results.map { |r| simplify_result(r) }
      rescue StandardError => e
        @logger.error "Quick search failed: #{e.message}"
        []
      end

      # Search with highlighting
      # @param query [String] Search query
      # @param options [Hash] Search options
      # @return [Hash] Results with highlighted snippets
      def search_with_highlighting(query, options = {})
        # Force highlighting on
        options = options.merge(enable_highlighting: true)
        search(query, options)
      end

      # Advanced search with filter support
      # @param query [String] Search query
      # @param filters [Hash] Search filters
      # @param options [Hash] Search options
      # @return [Hash] Filtered search results
      def advanced_search(query, filters, options = {})
        options[:filters] = filters
        search(query, options)
      end

      # Multi-language search
      # @param query [String] Search query
      # @param languages [Array<String>] Target languages
      # @param options [Hash] Search options
      # @return [Hash] Results from all languages
      def multilingual_search(query, languages, options = {})
        all_results = []
        total_time = 0

        languages.each do |lang|
          lang_results = search(query, options.merge(language: lang))
          all_results.concat(lang_results[:results].map { |r| r.merge(language: lang) })
          total_time += lang_results[:metadata][:execution_time_ms]
        rescue StandardError => e
          @logger.error "Search failed for language #{lang}: #{e.message}"
        end

        # Sort by rank score across all languages
        all_results.sort_by! { |r| -(r[:rank_score] || 0) }

        # Apply limit
        limit = options[:limit] || config[:default_limit]
        all_results = all_results.first(limit)

        {
          query: query,
          languages: languages,
          results: all_results,
          metadata: {
            total_count: all_results.length,
            execution_time_ms: total_time,
            multilingual: true
          }
        }
      end

      # Search suggestions (auto-complete)
      # @param prefix [String] Query prefix
      # @param options [Hash] Options
      # @return [Array] Suggestion list
      def suggestions(prefix, options = {})
        return [] if prefix.to_s.strip.length < 2

        limit = options[:limit] || 10
        language = options[:language] || config[:default_language]

        # Simple implementation - in production, use a dedicated suggest index
        suggestions = db[:section_fts]
                      .join(:source_sections, id: Sequel[:section_fts][:section_id])
                      .select(
                        Sequel[:source_sections][:content]
                      )
                      .where do
                        (Sequel[:section_fts][:language] =~ language) &
                          (Sequel[:source_sections][:content] =~ /#{prefix}/i)
        end
          .limit(limit * 10) # Get more to process
          .map { |row| row[:content] }

        # Extract words starting with prefix
        words = suggestions.flat_map { |text| extract_words(text, prefix) }

        # Count frequencies and return top suggestions
        word_freq = words.group_by(&:downcase).transform_values(&:count)
        word_freq
          .sort_by { |_, count| -count }
          .first(limit)
          .map { |word, _| word }
      rescue StandardError => e
        @logger.error "Suggestions generation failed: #{e.message}"
        []
      end

      # Get search statistics
      # @return [Hash] Search statistics
      def statistics
        {
          total_indexed: fulltext_manager.stats[:total_indexed],
          search_performance: get_performance_stats,
          language_distribution: get_language_distribution,
          popular_queries: get_popular_queries
        }
      rescue StandardError => e
        @logger.error "Failed to get statistics: #{e.message}"
        {}
      end

      private

      # Validate search query
      def validate_query(query)
        return 'Query cannot be nil' if query.nil?
        return 'Query cannot be empty' if query.strip.empty?

        length = query.strip.length
        if length < config[:min_search_length]
          return "Query too short (minimum #{config[:min_search_length]} characters)"
        end

        if length > config[:max_search_length]
          return "Query too long (maximum #{config[:max_search_length]} characters)"
        end

        nil
      end

      # Analyze query to extract metadata
      def analyze_query(query)
        @query_parser.parse_advanced_query(query)
      end

      # Detect language for query
      def detect_language(query)
        @query_parser.detect_language(query)
      end

      # Extract filters from options
      def extract_filters(options)
        filters = {}
        filters[:document_ids] = options[:document_ids] if options[:document_ids]
        filters[:tag_ids] = options[:tag_ids] if options[:tag_ids]
        filters[:date_from] = options[:date_from] if options[:date_from]
        filters[:date_to] = options[:date_to] if options[:date_to]
        filters
      end

      # Format search results with metadata
      def format_search_results(results, options)
        results.map.with_index do |result, index|
          formatted = {
            section_id: result[:section_id],
            rank_score: result[:rank_score],
            rank: index + 1
          }

          # Add highlight if available and enabled
          formatted[:highlight] = result[:highlight] if result[:highlight] && config[:enable_highlighting]

          # Include content if requested
          if options[:include_content]
            section = get_section_content(result[:section_id])
            formatted[:content] = section[:content]
            formatted[:title] = section[:title]
          end

          # Include metadata if requested
          if options[:include_metadata]
            metadata = get_section_metadata(result[:section_id])
            formatted.merge!(metadata)
          end

          formatted
        end
      end

      # Get section content
      def get_section_content(section_id)
        @fulltext_manager.db[:source_sections]
                         .where(id: section_id)
                         .select(:content, :section_title)
                         .first || {}
      end

      # Get section metadata
      def get_section_metadata(section_id)
        dataset = @fulltext_manager.db[:source_sections]
                                   .where(Sequel[:source_sections][:id] => section_id)
                                   .left_join(:source_documents, id: Sequel[:source_sections][:document_id])
                                   .select(
                                     Sequel[:source_documents][:id].as(:document_id),
                                     Sequel[:source_documents][:title].as(:document_title),
                                     Sequel[:source_documents][:author],
                                     Sequel[:source_documents][:publication_date],
                                     Sequel[:source_sections][:section_number],
                                     Sequel[:source_documents][:metadata]
                                   )

        result = dataset.first
        return {} unless result

        metadata = {
          document_id: result[:document_id],
          document_title: result[:document_title],
          author: result[:author],
          publication_date: result[:publication_date],
          section_number: result[:section_number]
        }

        metadata.merge!(result[:metadata]) if result[:metadata]
        metadata
      end

      # Simplify result for quick search
      def simplify_result(result)
        {
          id: result[:section_id],
          rank: result[:rank_score]
        }
      end

      # Generate search suggestions
      def generate_suggestions(query, language)
        # Simple implementation - find similar terms
        suggestions = []

        # Split query into words
        words = query.strip.split(/\s+/)

        words.each do |word|
          next if word.length < 3

          # Find similar terms in the index
          similar = @fulltext_manager.db[:section_fts]
                                     .join(:source_sections, id: Sequel[:section_fts][:section_id])
                                     .select(
                                       Sequel.function(:substring, Sequel[:source_sections][:content],
                                                       /\b#{word[0..3]}\w*/i).as(:term)
                                     )
                                     .where(Sequel[:section_fts][:language] =~ language)
                                     .map { |row| row[:term] }
                                     .compact
                                     .uniq

          suggestions.concat(similar)
        end

        suggestions.uniq.first(3)
      end

      # Extract words starting with prefix
      def extract_words(text, prefix)
        # Find word boundaries
        words = text.scan(/\b\w+/)
        words.select { |w| w.downcase.start_with?(prefix.downcase) }
      end

      # Get performance statistics
      def get_performance_stats
        {
          average_response_time: 0,
          slowest_queries: [],
          total_searches: 0
        }
      end

      # Get language distribution
      def get_language_distribution
        @fulltext_manager.db[:section_fts]
                         .select(:language, Sequel.function(:count, '*').as(:count))
                         .group(:language)
                         .map { |row| { language: row[:language], count: row[:count] } }
      end

      # Get popular search queries
      def get_popular_queries
        @fulltext_manager.db[:search_logs]
                         .select(:query, Sequel.function(:count, '*').as(:count))
                         .where(Sequel[:created_at] > (Time.now - 86_400)) # Last 24 hours
                         .group(:query)
                         .order(Sequel.desc(:count))
                         .limit(10)
                         .map { |row| { query: row[:query], count: row[:count] } }
      end

      # Log search query
      def log_search(query, result_count, execution_time, error = nil)
        # Skip logging validation errors (nil/empty queries)
        return if query.nil? || query.to_s.strip.empty?

        begin
          # Skip logging if database or fulltext_manager is not available
          return unless @fulltext_manager && @fulltext_manager.respond_to?(:db) && @fulltext_manager.db

          # Build insert hash without error_message column (not in migration)
          log_data = {
            query: query.to_s,
            search_type: 'fulltext',
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
    end

    # Custom errors
    module Errors
      class FulltextSearchServiceError < StandardError; end
    end
  end
end
