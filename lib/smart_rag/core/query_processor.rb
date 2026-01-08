require_relative '../services/embedding_service'
require_relative '../services/tag_service'
require_relative '../services/vector_search_service'
require_relative '../services/fulltext_search_service'
require_relative '../services/hybrid_search_service'
require_relative '../services/summarization_service'
require_relative '../errors'

module SmartRAG
  module Core
    # QueryProcessor handles natural language queries and generates responses
    class QueryProcessor
      attr_reader :embedding_service, :tag_service, :vector_search_service,
                  :fulltext_search_service, :hybrid_search_service,
                  :summarization_service, :embedding_manager, :config, :logger

      # Initialize the query processor
      # @param config [Hash] Configuration options
      # @option config [EmbeddingService] :embedding_service Embedding service instance
      # @option config [TagService] :tag_service Tag service instance
      # @option config [VectorSearchService] :vector_search_service Vector search service instance
      # @option config [FulltextSearchService] :fulltext_search_service Fulltext search service instance
      # @option config [HybridSearchService] :hybrid_search_service Hybrid search service instance
      # @option config [SummarizationService] :summarization_service Summarization service instance
      # @option config [Logger] :logger Logger instance
      def initialize(config = {})
        @config = config
        @logger = config[:logger] || Logger.new(STDOUT)

        # Initialize services (use provided or create defaults)
        @embedding_service = config[:embedding_service] || Services::EmbeddingService.new(config)
        @tag_service = config[:tag_service] || Services::TagService.new(config)

        # Create embedding manager for vector search (used for tag-enhanced search)
        @embedding_manager = config[:embedding_manager] || ::SmartRAG::Core::Embedding.new(config)
        @vector_search_service = config[:vector_search_service] || Services::VectorSearchService.new(
          @embedding_manager, config
        )

        # Create fulltext manager for fulltext search
        # Note: FulltextManager requires a database connection as first parameter
        db = config[:db] || ::SmartRAG.db
        fulltext_manager = config[:fulltext_manager] || ::SmartRAG::Core::FulltextManager.new(db, config)
        query_parser = config[:query_parser] || ::SmartRAG::Parsers::QueryParser.new
        @fulltext_search_service = config[:fulltext_search_service] || Services::FulltextSearchService.new(
          fulltext_manager, query_parser, config
        )

        @hybrid_search_service = config[:hybrid_search_service] || Services::HybridSearchService.new(
          @embedding_manager,
          fulltext_manager,
          config
        )
        @summarization_service = config[:summarization_service] || Services::SummarizationService.new(config)

        @logger.info 'QueryProcessor initialized with all services'
      rescue StandardError => e
        @logger.error "Failed to initialize QueryProcessor: #{e.message}" if @logger
        raise
      end

      # Process a natural language query and return search results
      # @param query_text [String] Natural language query
      # @param options [Hash] Processing options
      # @option options [Symbol] :language Query language (:zh_cn, :zh_tw, :en, :ja)
      # @option options [Integer] :limit Maximum results (default: 10)
      # @option options [Float] :threshold Similarity threshold (default: 0.3)
      # @option options [Symbol] :search_type Search type (:vector, :fulltext, :hybrid)
      # @option options [Array<Integer>] :document_ids Filter by document IDs
      # @option options [Array<String>, Array<Tag>] :tags Tags to boost results
      # @option options [Boolean] :generate_tags Whether to generate tags from query (default: false)
      # @return [Hash] Search results with metadata
      def process_query(query_text, options = {})
        raise ArgumentError, 'Query text cannot be nil or empty' if query_text.to_s.strip.empty?

        logger.info "Processing query: #{query_text[0..100]}..."

        # Validate search type first
        search_type = options[:search_type] || :hybrid
        unless %i[vector fulltext hybrid].include?(search_type)
          raise ArgumentError, "Invalid search type: #{search_type}"
        end

        # Detect language if not provided
        options[:language] ||= detect_language(query_text)
        language = options[:language]
        logger.info "Detected language: #{language}"

        # Generate query tags if requested
        query_tags = []
        if options[:generate_tags]
          logger.info 'Generating tags from query...'
          generated_tags = tag_service.generate_tags(query_text, nil, [language],
                                                     max_content_tags: 5, include_category: false)
          query_tags = generated_tags[:content_tags] || []
          logger.info "Generated #{query_tags.size} tags: #{query_tags.join(', ')}"
        end

        # Combine user-provided tags with generated tags
        all_tags = options[:tags] ? ensure_tag_objects(options[:tags]) : []
        all_tags.concat(ensure_tag_objects(query_tags)) if query_tags.any?

        # Generate query embedding for vector search
        query_embedding = generate_query_embedding(query_text, options)

        # Execute search based on type
        search_results = case search_type
                         when :vector
                           logger.info 'Performing vector search...'
                           perform_vector_search(query_embedding, all_tags, options)
                         when :fulltext
                           logger.info 'Performing fulltext search...'
                           perform_fulltext_search(query_text, options)
                         when :hybrid
                           logger.info 'Performing hybrid search...'
                           perform_hybrid_search(query_text, query_embedding, all_tags, options)
                         end

        logger.info "Search completed. Found #{search_results[:results].size} results"

        # Enrich results with additional metadata
        enriched = enrich_results(search_results, query_text, options)
        apply_domain_boost(enriched, query_text, options) if search_type == :hybrid
        enriched
      rescue ArgumentError
        raise
      rescue StandardError => e
        logger.error "Query processing failed: #{e.message}"
        logger.error e.backtrace.join("\n")
        raise ::SmartRAG::Errors::QueryProcessingError, "Query processing failed: #{e.message}"
      end

      # Generate a natural language response based on search results
      # @param question [String] Original question
      # @param search_results [Hash] Results from process_query
      # @param options [Hash] Response generation options
      # @option options [Symbol] :language Response language
      # @option options [Integer] :max_length Maximum response length
      # @option options [Boolean] :include_sources Whether to include source references (default: true)
      # @return [Hash] Response with answer and metadata
      def generate_response(question, search_results, options = {})
        raise ArgumentError, 'Question cannot be nil or empty' if question.to_s.strip.empty?
        raise ArgumentError, 'Search results cannot be nil' if search_results.nil?

        logger.info "Generating response for question: #{question[0..50]}..."
        logger.info "Search results: #{search_results.inspect[0..200]}"

        # Extract results and context
        results = search_results[:results] || []
        logger.info "Number of results: #{results.size}"

        context = extract_context_for_response(results, options)
        logger.info "Context extracted: #{context.length} chars"

        if context.empty?
          logger.warn 'No context available for response generation'
          return {
            answer: "I don't have enough information to answer this question.",
            sources: [],
            confidence: 0.0
          }
        end

        # Generate response using summarization service
        logger.info 'Calling summarization service...'
        response = summarization_service.summarize_search_results(question, context, options)
        logger.info "Summarization service returned: #{response.inspect[0..200]}"

        # Add source references if requested
        if options.fetch(:include_sources, true)
          sources = extract_sources(results)
          response[:sources] = sources
        end

        logger.info 'Response generated successfully'
        response
      rescue ArgumentError
        raise
      rescue StandardError => e
        logger.error "Response generation failed: #{e.message}"
        raise ::SmartRAG::Errors::ResponseGenerationError, "Response generation failed: #{e.message}"
      end

      # Process a query and generate a response in one step
      # @param question [String] Natural language question
      # @param options [Hash] Processing and response options
      # @return [Hash] Complete response with answer, sources, and metadata
      def ask(question, options = {})
        logger.info "Processing ask request: #{question[0..50]}..."

        # Process the query to get search results
        search_results = process_query(question, options)

        # Generate response from search results
        response = generate_response(question, search_results, options)

        # Combine everything
        {
          question: question,
          answer: response[:answer],
          sources: response[:sources],
          search_results: search_results[:results],
          metadata: {
            search_type: search_results[:search_type],
            total_results: search_results[:total_results],
            processing_time_ms: search_results[:processing_time_ms],
            confidence: response[:confidence]
          }
        }
      rescue StandardError => e
        logger.error "Ask request failed: #{e.message}"
        raise
      end

      private

      def detect_language(text)
        # Simple language detection based on character ranges
        # Check for Japanese hiragana/katakana first (more specific than Chinese kanji)
        return :ja if text.match?(/[\u3040-\u309f\u30a0-\u30ff]/)
        return :zh if text.match?(/[\u4e00-\u9fff]/)

        :en # Default to English
      rescue StandardError => e
        logger.warn "Language detection failed: #{e.message}, defaulting to English"
        :en
      end

      def generate_query_embedding(query_text, options = {})
        logger.debug 'Generating query embedding...'
        embedding_service.generate_embedding(query_text, options)
      rescue StandardError => e
        logger.error "Failed to generate query embedding: #{e.message}"
        raise
      end

      def perform_vector_search(query_embedding, tags, options = {})
        limit = options[:limit] || 10
        threshold = options[:threshold] || 0.3

        results = if tags.any?
                    # Use tag-enhanced search if tags are provided (via embedding manager)
                    embedding_manager.search_by_vector_with_tags(
                      query_embedding,
                      tags,
                      options.merge(limit: limit, threshold: threshold, document_ids: options[:document_ids])
                    )
                  else
                    # Regular vector search (via vector search service)
                    # Extract just the results array from the service response
                    search_response = vector_search_service.search_by_vector(
                      query_embedding,
                      options.merge(limit: limit, threshold: threshold, document_ids: options[:document_ids])
                    )
                    # Handle both hash response and direct array
                    if search_response.is_a?(Hash)
                      search_response[:results] || []
                    else
                      search_response
                    end
                  end

        {
          results: results,
          search_type: :vector,
          total_results: results.size
        }
      rescue StandardError => e
        logger.error "Vector search failed: #{e.message}"
        raise
      end

      def perform_fulltext_search(query_text, options = {})
        language = options[:language] || :en
        limit = options[:limit] || 10

        # Fulltext search service returns a complete response hash with query, results, and metadata
        # No need to wrap it further
        response = fulltext_search_service.search(
          query_text,
          options.merge(
            language: language,
            limit: limit
          )
        )

        # Ensure response has the expected structure for our pipeline
        # It should already have :results, but let's normalize
        {
          results: response[:results] || [],
          search_type: :fulltext,
          total_results: response.dig(:metadata, :total_count) || response[:results]&.length || 0
        }
      rescue StandardError => e
        logger.error "Fulltext search failed: #{e.message}"
        raise
      end

      def perform_hybrid_search(query_text, query_embedding, tags, options = {})
        limit = options[:limit] || 10

        # Build filters by merging existing filters with document_ids and tags
        search_filters = options[:filters] || {}
        search_filters[:document_ids] = options[:document_ids] if options[:document_ids]
        search_filters[:tags] = tags if tags && !tags.empty?

        # Hybrid search service expects query text and can optionally use pre-computed query_embedding
        # This avoids re-generating the embedding for efficiency
        search_response = hybrid_search_service.search(
          query_text,
          options.merge(
            limit: limit,
            query_embedding: query_embedding,
            filters: search_filters.compact
          )
        )

        # Extract the actual results array from the hybrid search response
        # Handle both mock format (direct array) and real format (hash with :results key)
        actual_results = if search_response.is_a?(Array)
                           # Mock format - direct array of results
                           search_response
                         else
                           # Real format - hash with :results key
                           search_response[:results] || []
                         end

        {
          results: actual_results,
          search_type: :hybrid,
          total_results: actual_results.size
        }
      rescue StandardError => e
        logger.error "Hybrid search failed: #{e.message}"
        raise
      end

      def enrich_results(search_results, query_text, options = {})
        # Normalize the search results into the expected format
        # search_results may have :total_results or :total_count, convert to metadata
        results = search_results[:results] || []

        # Build the standardized response format
        response = {
          query: query_text,
          results: results,
          metadata: {
            total_count: search_results[:total_results] || search_results[:total_count] || results.length,
            execution_time_ms: calculate_processing_time,
            language: options[:language] || :en
          }
        }

        # Add additional metadata from search_results if present
        response[:metadata][:search_type] = search_results[:search_type] if search_results[:search_type]

        # Add processing timestamp
        response[:metadata][:processed_at] = Time.now

        response
      rescue StandardError => e
        # If enrichment fails, return basic results
        logger.error "Failed to enrich results: #{e.message}"
        {
          query: query_text,
          results: results,
          metadata: {
            total_count: results.length,
            execution_time_ms: 0,
            language: options[:language] || :en,
            error: e.message
          }
        }
      end

      def extract_context_for_response(results, options = {})
        max_context_length = options[:max_context_length] || 4000
        context_parts = []

        # Ensure results is an array
        results = Array(results)

        results.first(5).each_with_index do |result, index|
          # Skip if result is nil
          next if result.nil?

          # Handle case where result is not a hash (might be an Embedding object or array)
          if result.is_a?(Hash)
            section = result[:section] || result[:embedding]&.section
          elsif result.respond_to?(:section)
            # It's likely an Embedding object
            section = result.section
          else
            logger.warn "Unexpected result format at index #{index}: #{result.class}"
            next
          end

          next unless section

          # Handle both hash and object sections
          if section.is_a?(Hash)
            # Section is a hash (from VectorSearchService)
            content = section[:content].to_s.strip
            next if content.empty?

            # Add section title if available
            context_parts << if section[:title] && !section[:title].empty?
                               "Section: #{section[:title]}\n#{content}"
                             else
                               content
                             end
          else
            # Section is a model object
            content = section.content.to_s.strip
            next if content.empty?

            # Add section title if available
            context_parts << if section.section_title && !section.section_title.empty?
                               "Section: #{section.section_title}\n#{content}"
                             else
                               content
                             end
          end
        end

        # Join and truncate if necessary
        full_context = context_parts.join("\n\n---\n\n")

        if full_context.length > max_context_length
          full_context = full_context[0...max_context_length] + '... (truncated)'
        end

        full_context
      end

      def extract_sources(results)
        sources = []

        results.first(5).each do |result|
          section = result[:section] || result[:embedding]&.section
          next unless section

          document = section.document
          next unless document

          sources << {
            document_id: document.id,
            document_title: document.title,
            section_id: section.id,
            section_title: section.section_title,
            url: document.url,
            relevance: result[:similarity] || result[:boosted_score] || 0
          }
        end

        sources
      end

      def ensure_tag_objects(tags)
        return [] unless tags

        tags.map do |tag|
          case tag
          when ::SmartRAG::Models::Tag
            tag
          when Integer
            ::SmartRAG::Models::Tag.find(id: tag) || raise(ArgumentError, "Tag not found: #{tag}")
          when String
            # Use find_or_create for string tags to ensure they exist
            ::SmartRAG::Models::Tag.find_or_create(tag)
          else
            raise ArgumentError, "Invalid tag type: #{tag.class}"
          end
        end
      end

      def calculate_processing_time
        # This would track actual processing time in a real implementation
        # For now, return 0 as placeholder
        0
      end

      def apply_domain_boost(response, _query_text, options)
        options ||= {}
        expected = Array(options[:expected_categories] || options[:expected_category]).compact
        return normalize_categories(response) if expected.empty?

        results = response[:results] || []
        return response if results.empty?

        normalize_categories(response)

        boosted = results.sort_by do |result|
          metadata = result[:metadata] || {}
          category = metadata[:category].to_s
          match = expected.any? { |exp| category.include?(exp) }
          match ? 0 : 1
        end

        response.merge(results: boosted)
      end

      def normalize_categories(response)
        results = response[:results] || []
        results.each do |result|
          metadata = result[:metadata] || {}
          normalized = normalize_category(metadata[:category], metadata[:document_title])
          metadata[:category] = normalized if normalized
          result[:metadata] = metadata
        end
        response.merge(results: results)
      end

      def normalize_category(category, _title)
        cat = category.to_s
        return cat if cat.empty?

        cat
      end
    end
  end
end
