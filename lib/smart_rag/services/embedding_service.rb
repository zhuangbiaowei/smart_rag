require_relative '../models/embedding'
require_relative '../models/source_section'
require 'smart_prompt'

module SmartRAG
  module Services
    # Service for managing embeddings generation, storage, and retrieval
    class EmbeddingService
      attr_reader :config, :logger, :smart_prompt_engine

      # Initialize the embedding service
      # @param config [Hash] Configuration options
      # @option config [String] :config_path Path to smart_prompt config (default: config/llm_config.yml)
      # @option config [Integer] :retries Number of retries for API calls (default: 3)
      # @option config [Integer] :timeout Timeout for API calls (default: 60)
      def initialize(config = {})
        config ||= {}
        @logger = Logger.new(STDOUT)
        @config = default_config.merge(config)
        @logger = @config[:logger] || @logger

        # Load workers
        workers_dir = File.join(File.dirname(__FILE__), '..', '..', '..', 'workers')
        Dir.glob(File.join(workers_dir, '*.rb')).each { |file| require file }

        # Initialize SmartPrompt engine
        config_path = @config[:config_path] || 'config/llm_config.yml'
        @smart_prompt_engine = SmartPrompt::Engine.new(config_path)
      rescue StandardError => e
        log_error('Failed to initialize SmartPrompt engine', e)
        raise
      end

      # Generate embeddings for a section
      # @param section [SourceSection] The section to generate embeddings for
      # @param options [Hash] Options for embedding generation
      # @return [Embedding] The generated embedding
      def generate_for_section(section, options = {})
        raise ArgumentError, 'Section cannot be nil' unless section
        raise ArgumentError, 'Section content cannot be empty' if section.content.to_s.strip.empty?

        text = prepare_section_text(section)
        vector = generate_embedding(text, options)

        create_embedding_record(section, vector, options)
      rescue StandardError => e
        section_id = section.respond_to?(:id) ? section.id : 'unknown'
        log_error("Failed to generate embedding for section #{section_id}", e)
        raise
      end

      # Batch generate embeddings for multiple sections
      # @param sections [Array<SourceSection>] Sections to generate embeddings for
      # @param options [Hash] Options for embedding generation
      # @return [Array<Embedding>] Generated embeddings
      def batch_generate(sections, options = {})
        raise ArgumentError, 'Sections array cannot be nil' unless sections
        return [] if sections.empty?

        logger.info "Generating embeddings for #{sections.size} sections"

        sections.each_slice(config[:batch_size]).flat_map do |batch|
          batch_generate_batch(batch, options)
        end
      rescue StandardError => e
        log_error('Failed to batch generate embeddings', e)
        raise
      end

      # Update existing embedding
      # @param embedding [Embedding] The embedding to update
      # @param options [Hash] Options for update
      # @return [Embedding] The updated embedding
      def update_embedding(embedding, options = {})
        raise ArgumentError, 'Embedding cannot be nil' unless embedding

        section = embedding.section
        raise ArgumentError, 'Section not found for embedding' unless section

        new_vector = generate_embedding(section.content, options)
        embedding.update(vector: new_vector)

        logger.info "Updated embedding #{embedding.id} for section #{section.id}"
        embedding
      rescue NoMethodError => e
        raise ArgumentError, 'Embedding cannot be nil' if e.message.include?('id')

        raise
      rescue StandardError => e
        embedding_id = embedding.respond_to?(:id) ? embedding.id : 'unknown'
        log_error("Failed to update embedding #{embedding_id}", e)
        raise
      end

      # Delete embeddings for a section
      # @param section [SourceSection] The section
      # @return [Integer] Number of deleted embeddings
      def delete_by_section(section)
        raise ArgumentError, 'Section cannot be nil' unless section

        deleted_count = Models::Embedding.delete_by_section(section.id)
        logger.info "Deleted #{deleted_count} embeddings for section #{section.id}"

        deleted_count
      rescue NoMethodError => e
        raise ArgumentError, 'Section cannot be nil' if e.message.include?('id')

        raise
      rescue StandardError => e
        section_id = section.respond_to?(:id) ? section.id : 'unknown'
        log_error("Failed to delete embeddings for section #{section_id}", e)
        raise
      end

      # Get embedding for a section (creates if not exists)
      # @param section [SourceSection] The section
      # @param options [Hash] Options
      # @return [Embedding] The embedding
      def get_or_create(section, options = {})
        existing = Models::Embedding.by_section(section.id).first
        return existing if existing

        generate_for_section(section, options)
      end

      # Recalculate all embeddings (useful when model changes)
      # @param options [Hash] Options
      # @option options [Integer] :batch_size Batch size (default: 100)
      # @option options [ProgressBar] :progress Progress bar (optional)
      # @return [Integer] Number of updated embeddings
      def recalculate_all(options = {})
        batch_size = options[:batch_size] || 100
        total_updated = 0

        Models::SourceSection.dataset.each_slice(batch_size) do |batch|
          batch.each do |section|
            get_or_create(section, options)
            total_updated += 1
          rescue StandardError => e
            log_error("Failed to recalculate embedding for section #{section.id}", e)
          end

          yield(batch.size, total_updated) if block_given?
        end

        logger.info "Recalculated #{total_updated} embeddings"
        total_updated
      end

      # Generate embedding for text
      # @param text [String] Text to generate embedding for
      # @param options [Hash] Generation options
      # @return [Array<Float>] Vector embedding
      def generate_embedding(text, options = {})
        max_retries = options[:retries] || config[:retries]
        timeout = options[:timeout] || config[:timeout]

        with_retry(max_retries: max_retries, timeout: timeout) do
          result = smart_prompt_engine.call_worker(:get_embedding, { text: text })
          raise 'No embedding returned from API' unless result

          # Debug: log vector info
          puts "[DEBUG] generate_embedding: text=#{text[0..50]}, result_type=#{result.class}, result_length=#{result.length}"
          puts "[DEBUG] generate_embedding: first 5 values=#{result[0..5]}"

          result
        end
      rescue StandardError => e
        log_error('Embedding generation failed', e)
        # Re-raise with more context
        raise StandardError,
              "Embedding generation failed: #{e.message} (input: #{text[0..100]}#{'...' if text.length > 100})"
      end

      private

      def prepare_section_text(section)
        parts = []
        parts << "Title: #{section.section_title}" if section.section_title && !section.section_title.strip.empty?
        parts << "Section: #{section.section_number}" if section.section_number
        parts << section.content

        parts.compact.join("\n\n")
      end

      def create_embedding_record(section, vector, _options = {})
        embedding = Models::Embedding.new(
          source_id: section.id,
          vector: pgvector(vector)
        )

        embedding.save!
        logger.info "Created embedding #{embedding.id} for section #{section.id}"

        embedding
      end

      def batch_generate_batch(batch, options = {})
        texts = batch.map { |section| prepare_section_text(section) }
        vectors = batch_generate_embeddings(texts, options)

        embedding_data = batch.map.with_index do |section, index|
          {
            source_id: section.id,
            vector: pgvector(vectors[index])
          }
        end

        Models::Embedding.batch_insert(embedding_data)

        # Reload embeddings from DB to return proper objects
        Models::Embedding.by_sections(batch.map(&:id))
      rescue StandardError => e
        logger.error "Failed to batch generate embeddings: #{e.message}"
        logger.error 'Falling back to individual generation'

        # Fallback to individual generation
        batch.map { |section| generate_for_section(section, options) }
      end

      def batch_generate_embeddings(texts, options = {})
        max_retries = options[:retries] || config[:retries]
        timeout = options[:timeout] || config[:timeout]

        # Process each text individually since smart_prompt doesn't have batch endpoint
        logger.info "Generating embeddings for #{texts.size} texts in batch"

        # Use Thread for parallel processing if needed
        # For now, process sequentially
        texts.map do |text|
          with_retry(max_retries: max_retries, timeout: timeout) do
            result = smart_prompt_engine.call_worker(:get_embedding, { text: text })
            raise 'No embedding returned from API' unless result

            result
          end
        end
      rescue StandardError => e
        logger.error "Batch embedding generation failed: #{e.message}"
        raise
      end

      def with_retry(max_retries:, timeout:)
        last_exception = nil

        max_retries.times do |attempt|
          Timeout.timeout(timeout) do
            return yield
          end
        rescue StandardError => e
          last_exception = e
          logger.warn "Attempt #{attempt + 1} failed: #{e.message}"

          # Exponential backoff
          sleep(2**attempt) if attempt < max_retries - 1
        end

        raise last_exception
      end

      def log_error(message, exception)
        active_logger = logger || @logger || Logger.new(STDOUT)
        active_logger.error "#{message}: #{exception.message}"
        active_logger.error exception.backtrace.join("\n")
      end

      def default_config
        {
          config_path: 'config/llm_config.yml',
          retries: 3,
          timeout: 60,
          batch_size: 100,
          logger: Logger.new(STDOUT)
        }
      end

      def pgvector(vector_array)
        "[#{vector_array.join(',')}]"
      end
    end
  end
end
