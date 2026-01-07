require_relative "smart_rag/version"
require_relative "smart_rag/config"
require_relative "smart_rag/errors"
require_relative "smart_rag/models"
require "sequel"
require "logger"

module SmartRAG
  class Error < StandardError; end

  # Database connection for models
  @db = nil
  @model_dependencies_loaded = false

  class << self
    attr_accessor :db

    # Load models and dependencies
    def load_models!
      require_relative "smart_rag/models"
    end

    def load_model_dependencies!
      return if @model_dependencies_loaded
      @model_dependencies_loaded = true

      require_relative "smart_rag/core/embedding"
      require_relative "smart_rag/core/document_processor"
      require_relative "smart_rag/services/embedding_service"
      require_relative "smart_rag/services/hybrid_search_service"
      require_relative "smart_rag/core/query_processor"
      require_relative "smart_rag/services/summarization_service"
      require_relative "smart_rag/services/tag_service"
    end
  end

  # Main SmartRAG class providing unified API interface
  class SmartRAG
    attr_reader :config, :query_processor, :tag_service, :document_processor, :logger

    def logger=(logger)
      @logger = logger
    end

    # Initialize SmartRAG with configuration
    def initialize(config_hash = {})
      @config = ::SmartRAG::Config.load(config_hash)
      @logger = @config[:logger] || Logger.new(STDOUT)

      # Initialize database connection first (this loads models)
      initialize_db_connection

      # Then load model dependencies (services and core that use models)
      ::SmartRAG.load_model_dependencies!

      # Finally initialize services
      initialize_services_components
    end

    # Knowledge base management interface

    # Add document to knowledge base
    def add_document(document_path, options = {})
      result = @document_processor.create_document(document_path, options)
      {
        document_id: result[:document].id,
        section_count: result[:sections].length,
        status: "success",
      }
    end

    # Remove document from knowledge base
    def remove_document(document_id)
      return { success: false, deleted_sections: 0, deleted_embeddings: 0 } unless document_id.to_s =~ /\A-?\d+\Z/

      doc_id_i = document_id.to_i
      @delete_mutex ||= Mutex.new
      result = nil

      @delete_mutex.synchronize do
        doc = ::SmartRAG::Models::SourceDocument[doc_id_i]
        if doc.nil?
          result = { success: false, deleted_sections: 0, deleted_embeddings: 0 }
        else
          section_ids = ::SmartRAG::Models::SourceSection.where(document_id: doc_id_i).select_map(:id)
          deleted_embeddings = section_ids.any? ? ::SmartRAG::Models::Embedding.where(source_id: section_ids).delete : 0
          deleted_sections = ::SmartRAG::Models::SourceSection.where(document_id: doc_id_i).delete
          deleted = ::SmartRAG.db["DELETE FROM source_documents WHERE id = ?", doc_id_i].delete

          result = {
            success: deleted > 0,
            deleted_sections: deleted_sections,
            deleted_embeddings: deleted_embeddings,
          }
        end
      end

      result
    rescue StandardError => e
      @logger.error "Error removing document #{document_id}: #{e.message}"
      { success: false, deleted_sections: 0, deleted_embeddings: 0 }
    end

    # Get document information
    def get_document(document_id)
      return nil unless document_id.to_s =~ /\A-?\d+\Z/

      document = ::SmartRAG::Models::SourceDocument[document_id.to_i]
      return nil unless document

      {
        id: document.id,
        title: document.title,
        description: document.description,
        author: document.author,
        created_at: document.created_at,
        updated_at: document.updated_at,
        section_count: document.sections.count,
        metadata: document.metadata,
      }
    rescue StandardError => e
      @logger.error "Error getting document #{document_id}: #{e.message}"
      nil
    end

    # List documents with pagination
    def list_documents(options = {})
      page = [options[:page]&.to_i || 1, 1].max
      per_page = options[:per_page]
      per_page = if per_page.nil? || per_page.to_s.empty?
          20
        else
          per_page.to_i
        end

      dataset = ::SmartRAG::Models::SourceDocument.dataset

      if options[:search] && !options[:search].empty?
        search_term = "%#{options[:search]}%"
        dataset = dataset.where(Sequel.ilike(:title, search_term))
      end

      total_count = dataset.count

      documents = dataset
        .order(Sequel.desc(:created_at))
        .limit(per_page)
        .offset((page - 1) * per_page)
        .map do |doc|
        {
          id: doc.id,
          title: doc.title,
          description: doc.description,
          author: doc.author,
          created_at: doc.created_at,
          section_count: doc.sections.count,
        }
      end

      {
        documents: documents,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: (total_count.to_f / per_page).ceil,
      }
    end

    # Search interface
    def search(query, options = {})
      if options.key?(:search_type) && options[:search_type].nil?
        raise ArgumentError, "Invalid search_type: nil. Must be 'hybrid', 'vector', or 'fulltext'"
      end

      search_type = (options[:search_type] || "hybrid").to_s

      case search_type
      when "hybrid"
        hybrid_search(query, options.merge(search_type: :hybrid))
      when "vector"
        vector_search(query, options.merge(search_type: :vector))
      when "fulltext"
        fulltext_search(query, options.merge(search_type: :fulltext))
      else
        raise ArgumentError, "Invalid search_type: #{search_type}. Must be 'hybrid', 'vector', or 'fulltext'"
      end
    end

    def vector_search(query, options = {})
      options = options.merge(search_type: :vector)
      query_processor.process_query(query, options)
    end

    def fulltext_search(query, options = {})
      options = options.merge(search_type: :fulltext)
      query_processor.process_query(query, options)
    end

    def hybrid_search(query, options = {})
      options = options.merge(search_type: :hybrid)
      query_processor.process_query(query, options)
    end

    # Get system statistics
    def statistics
      {
        document_count: ::SmartRAG::Models::SourceDocument.count,
        section_count: ::SmartRAG::Models::SourceSection.count,
        topic_count: ::SmartRAG::Models::ResearchTopic.count,
        tag_count: ::SmartRAG::Models::Tag.count,
        embedding_count: ::SmartRAG::Models::Embedding.count,
      }
    rescue StandardError => e
      @logger.error "Failed to get statistics: #{e.message}"
      {
        document_count: 0,
        section_count: 0,
        topic_count: 0,
        tag_count: 0,
        embedding_count: 0,
        error: e.message,
      }
    end

    private

    def initialize_db_connection
      db_config = @config[:database]

      if db_config.nil? || db_config.empty?
        @logger.warn "Database configuration missing or empty, initializing in limited mode"
        ::SmartRAG.db = nil
        ::SmartRAG::Models.db = nil
        return
      end

      begin
        if ::SmartRAG::Models.db
          db = ::SmartRAG::Models.db
          ::SmartRAG.db = db
          @logger.info "Using existing Model database connection"
        elsif ::SmartRAG.db
          db = ::SmartRAG.db
          ::SmartRAG::Models.db = db
          @logger.info "Using existing SmartRAG database connection and syncing with Models"
        else
          db = Sequel.connect(db_config)
          ::SmartRAG.db = db
          ::SmartRAG::Models.db = db
          @logger.info "Created new database connection"
        end
      rescue Sequel::Error => e
        @logger.error "Failed to initialize database: #{e.message}"
        @logger.warn "SmartRAG initialized in limited mode without database"
        ::SmartRAG.db = nil
        ::SmartRAG::Models.db = nil
      end
    end

    def initialize_services_components
      if ::SmartRAG.db.nil?
        @query_processor = nil
        @tag_service = ::SmartRAG::Services::TagService.new(@config[:llm] || {})
        @document_processor = nil
        return
      end

      begin
        # Use the actual database connection, not the config hash
        db_connection = ::SmartRAG.db

        embedding_manager = ::SmartRAG::Core::Embedding.new(@config[:database])
        fulltext_manager = ::SmartRAG::Core::FulltextManager.new(db_connection, @config[:fulltext] || {})

        @query_processor = ::SmartRAG::Core::QueryProcessor.new(
          config: @config,
          embedding_manager: embedding_manager,
          fulltext_manager: fulltext_manager,
        )

        @tag_service = ::SmartRAG::Services::TagService.new(@config[:llm])

        # Create embedding service for document processor
        embedding_service = ::SmartRAG::Services::EmbeddingService.new(@config[:embedding] || {})

        @document_processor = ::SmartRAG::Core::DocumentProcessor.new(
          embedding_manager: embedding_service,
          tag_service: @tag_service,
          config: @config,
        )
      rescue StandardError => e
        @logger.error "Failed to initialize services: #{e.message}"
        @query_processor = nil
        @tag_service = ::SmartRAG::Services::TagService.new(@config[:llm] || {})
        @document_processor = nil
      end
    end

    def detect_language(content)
      if content.match?(/[\u4e00-\u9fff]/)
        :zh
      elsif content.match?(/[\u3040-\u309f\u30a0-\u30ff]/)
        :ja
      else
        :en
      end
    end
  end
end
