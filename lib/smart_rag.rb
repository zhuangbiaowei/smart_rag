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
          deleted = ::SmartRAG::Models::SourceDocument.where(id: doc_id_i).delete

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
        metadata: begin
                    if document.metadata.is_a?(String) && !document.metadata.strip.empty?
                      JSON.parse(document.metadata)
                    else
                      document.metadata
                    end
                  rescue StandardError
                    document.metadata
                  end,
      }
    rescue StandardError => e
      @logger.error "Error getting document #{document_id}: #{e.message}"
      nil
    end

    # List documents with pagination
    def list_documents(options = {})
      page = [options[:page]&.to_i || 1, 1].max
      per_page_raw = options[:per_page]
      per_page = if per_page_raw.nil? || per_page_raw.to_s.empty?
                   20
                 elsif per_page_raw.to_s =~ /\A-?\d+\Z/
                   per_page_raw.to_i
                 else
                   20
                 end
      per_page = [[per_page, 1].max, 100].min

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
        total_pages: [(total_count.to_f / per_page).ceil, 1].max,
      }
    end

    # List tags with pagination
    def list_tags(options = {})
      page = [options[:page]&.to_i || 1, 1].max
      per_page_raw = options[:per_page]
      per_page = if per_page_raw.nil? || per_page_raw.to_s.empty?
                   20
                 elsif per_page_raw.to_s =~ /\A-?\d+\Z/
                   per_page_raw.to_i
                 else
                   20
                 end
      per_page = [[per_page, 1].max, 100].min

      dataset = ::SmartRAG::Models::Tag.dataset

      if options[:search] && !options[:search].empty?
        search_term = "%#{options[:search]}%"
        dataset = dataset.where(Sequel.ilike(:name, search_term))
      end

      total_count = dataset.count

      tags = dataset
        .order(Sequel.asc(:name))
        .limit(per_page)
        .offset((page - 1) * per_page)
        .map do |tag|
        {
          id: tag.id,
          name: tag.name,
          parent_id: tag.parent_id,
          section_count: tag.respond_to?(:sections) ? tag.sections.count : 0
        }
      end

      {
        tags: tags,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: (total_count.to_f / per_page).ceil,
      }
    rescue StandardError => e
      @logger.error "Error listing tags: #{e.message}"
      {
        tags: [],
        total_count: 0,
        page: 1,
        per_page: per_page || 20,
        total_pages: 0,
        error: e.message,
      }
    end

    # Search interface
    def search(query, options = {})
      normalized_query = query.to_s.strip
      raise ArgumentError, "Query text cannot be nil or empty" if normalized_query.empty?
      raise ArgumentError, "Query too short" if normalized_query.length < 2
      raise ArgumentError, "Query too long" if normalized_query.length > 1000

      if options.key?(:search_type) && options[:search_type].nil?
        raise ArgumentError, "Invalid search_type: nil. Must be 'hybrid', 'vector', or 'fulltext'"
      end

      search_type = (options[:search_type] || "hybrid").to_s

      case search_type
      when "hybrid"
        hybrid_search(normalized_query, options.merge(search_type: :hybrid))
      when "vector"
        vector_search(normalized_query, options.merge(search_type: :vector))
      when "fulltext"
        fulltext_search(normalized_query, options.merge(search_type: :fulltext))
      else
        raise ArgumentError, "Invalid search_type: #{search_type}. Must be 'hybrid', 'vector', or 'fulltext'"
      end
    end

    def vector_search(query, options = {})
      options = options.merge(search_type: :vector)
      return vector_error_response(query, options, "Search service unavailable") if query_processor.nil?
      return vector_error_response(query, options, "Search service unavailable") unless query_processor.respond_to?(:process_query)

      query_processor.process_query(query, options)
    rescue StandardError => e
      @logger.error "Vector search failed: #{e.message}"
      vector_error_response(query, options, e.message)
    end

    def fulltext_search(query, options = {})
      options = options.merge(search_type: :fulltext)
      return fulltext_error_response(query, options, "Search service unavailable") if query_processor.nil?
      return fulltext_error_response(query, options, "Search service unavailable") unless query_processor.respond_to?(:process_query)

      query_processor.process_query(query, options)
    rescue StandardError => e
      @logger.error "Fulltext search failed: #{e.message}"
      fulltext_error_response(query, options, e.message)
    end

    def hybrid_search(query, options = {})
      options = options.merge(search_type: :hybrid)
      return hybrid_error_response(query, options, "Search service unavailable") if query_processor.nil?
      return hybrid_error_response(query, options, "Search service unavailable") unless query_processor.respond_to?(:process_query)

      query_processor.process_query(query, options)
    rescue StandardError => e
      @logger.error "Hybrid search failed: #{e.message}"
      hybrid_error_response(query, options, e.message)
    end

    # Generate tags for content
    def generate_tags(content, options = {})
      return { content_tags: [], category_tags: [] } if content.to_s.strip.empty?

      context = options[:context]
      max_tags = options[:max_tags]
      tag_options = {}
      tag_options[:max_tags] = max_tags if max_tags

      result = tag_service.generate_tags(content, context, [:en], tag_options)
      {
        content_tags: result[:content_tags] || [],
        category_tags: result[:category_tags] || result[:categories] || []
      }
    end

    # Topic APIs
    def create_topic(title, description = nil, options = {})
      if description.is_a?(Hash)
        options = description
        description = options[:description]
      end

      topic = ::SmartRAG::Models::ResearchTopic.create!(
        name: title,
        description: description || options[:description]
      )

      Array(options[:tags]).each do |tag_name|
        next if tag_name.to_s.strip.empty?

        tag = ::SmartRAG::Models::Tag.find_or_create(tag_name.to_s.strip)
        ::SmartRAG::Models::ResearchTopicTag.find_or_create(
          research_topic_id: topic.id,
          tag_id: tag.id
        )
      end

      Array(options[:document_ids]).each do |document_id|
        add_document_to_topic(topic.id, document_id)
      end

      topic_payload(topic)
    end

    def get_topic(topic_id)
      return nil unless topic_id.to_s =~ /\A-?\d+\Z/

      topic = ::SmartRAG::Models::ResearchTopic[topic_id.to_i]
      return nil unless topic

      topic_payload(topic)
    rescue StandardError => e
      @logger.error "Error getting topic #{topic_id}: #{e.message}"
      nil
    end

    def list_topics(options = {})
      page = [options[:page]&.to_i || 1, 1].max
      per_page_raw = options[:per_page]
      per_page = if per_page_raw.nil? || per_page_raw.to_s.empty?
                   20
                 elsif per_page_raw.to_s =~ /\A-?\d+\Z/
                   per_page_raw.to_i
                 else
                   20
                 end
      per_page = 1 if per_page <= 0
      per_page = [per_page, 100].min

      dataset = ::SmartRAG::Models::ResearchTopic.dataset
      if options[:search] && !options[:search].to_s.strip.empty?
        term = "%#{options[:search]}%"
        dataset = dataset.where(Sequel.ilike(:name, term)).or(Sequel.ilike(:description, term))
      end

      total_count = dataset.count
      topics = dataset.order(Sequel.desc(:created_at)).limit(per_page).offset((page - 1) * per_page).all

      {
        topics: topics.map { |topic| topic_payload(topic) },
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: (total_count.to_f / per_page).ceil
      }
    end

    def update_topic(topic_id, attributes = {})
      return nil unless topic_id.to_s =~ /\A-?\d+\Z/
      return nil unless attributes.is_a?(Hash)
      return nil if attributes.key?(:title) && attributes[:title].nil?

      topic = ::SmartRAG::Models::ResearchTopic[topic_id.to_i]
      return nil unless topic

      updates = {}
      updates[:name] = attributes[:title] if attributes.key?(:title)
      updates[:description] = attributes[:description] if attributes.key?(:description)
      topic.update(updates) unless updates.empty?

      if attributes.key?(:tags)
        ::SmartRAG::Models::ResearchTopicTag.where(research_topic_id: topic.id).delete
        Array(attributes[:tags]).each do |tag_name|
          next if tag_name.to_s.strip.empty?

          tag = ::SmartRAG::Models::Tag.find_or_create(tag_name.to_s.strip)
          ::SmartRAG::Models::ResearchTopicTag.find_or_create(
            research_topic_id: topic.id,
            tag_id: tag.id
          )
        end
      end

      topic_payload(topic)
    rescue StandardError => e
      @logger.error "Error updating topic #{topic_id}: #{e.message}"
      nil
    end

    def delete_topic(topic_id)
      return { success: false } unless topic_id.to_s =~ /\A-?\d+\Z/

      deleted = ::SmartRAG::Models::ResearchTopic.where(id: topic_id.to_i).delete
      { success: deleted > 0, topic_id: topic_id.to_i }
    rescue StandardError => e
      @logger.error "Error deleting topic #{topic_id}: #{e.message}"
      { success: false, topic_id: topic_id.to_i }
    end

    def add_document_to_topic(topic_id, document_id)
      return { success: false, added_sections: 0 } unless topic_id.to_s =~ /\A-?\d+\Z/

      topic = ::SmartRAG::Models::ResearchTopic[topic_id.to_i]
      return { success: false, added_sections: 0 } unless topic

      sections = ::SmartRAG::Models::SourceSection.where(document_id: document_id.to_i).all
      added_sections = 0

      sections.each do |section|
        existing = ::SmartRAG::Models::ResearchTopicSection.find(
          research_topic_id: topic.id,
          section_id: section.id
        )
        next if existing

        ::SmartRAG::Models::ResearchTopicSection.create(
          research_topic_id: topic.id,
          section_id: section.id
        )
        added_sections += 1
      end

      { success: true, topic_id: topic.id, document_id: document_id.to_i, added_sections: added_sections }
    rescue StandardError => e
      @logger.error "Error adding document #{document_id} to topic #{topic_id}: #{e.message}"
      { success: false, topic_id: topic_id.to_i, document_id: document_id.to_i, added_sections: 0 }
    end

    def remove_document_from_topic(topic_id, document_id)
      return { success: false, deleted_sections: 0 } unless topic_id.to_s =~ /\A-?\d+\Z/

      topic = ::SmartRAG::Models::ResearchTopic[topic_id.to_i]
      return { success: false, deleted_sections: 0 } unless topic

      section_ids = ::SmartRAG::Models::SourceSection.where(document_id: document_id.to_i).select_map(:id)
      deleted_sections = if section_ids.empty?
                           0
                         else
                           ::SmartRAG::Models::ResearchTopicSection
                             .where(research_topic_id: topic.id, section_id: section_ids)
                             .delete
                         end

      { success: true, deleted_sections: deleted_sections }
    rescue StandardError => e
      @logger.error "Error removing document #{document_id} from topic #{topic_id}: #{e.message}"
      { success: false, deleted_sections: 0 }
    end

    def get_topic_recommendations(topic_id, limit: 5)
      topic = ::SmartRAG::Models::ResearchTopic[topic_id.to_i]
      return { topic_id: topic_id.to_i, recommendations: [] } unless topic

      tag_ids = ::SmartRAG::Models::ResearchTopicTag.where(research_topic_id: topic.id).select_map(:tag_id)
      recommendations = if tag_ids.empty?
                          []
                        else
                          ::SmartRAG::Models::ResearchTopicTag
                            .where(tag_id: tag_ids)
                            .exclude(research_topic_id: topic.id)
                            .group_and_count(:research_topic_id)
                            .order(Sequel.desc(:count))
                            .limit(limit)
                            .map do |row|
                              related = ::SmartRAG::Models::ResearchTopic[row[:research_topic_id]]
                              next unless related

                              {
                                topic_id: related.id,
                                title: related.name,
                                score: row[:count]
                              }
                            end
                            .compact
                        end

      { topic_id: topic.id, recommendations: recommendations }
    rescue StandardError => e
      @logger.error "Error getting topic recommendations for #{topic_id}: #{e.message}"
      { topic_id: topic_id.to_i, recommendations: [] }
    end

    # Search log APIs
    def search_logs(limit: 50, search_type: nil, **_options)
      max_limit = [limit.to_i, 1000].min
      return [] if max_limit <= 0

      dataset = ::SmartRAG::Models::SearchLog.dataset
      dataset = dataset.where(search_type: search_type.to_s) if search_type && !search_type.to_s.empty?

      dataset
        .order(Sequel.desc(:created_at))
        .limit(max_limit)
        .all
        .map do |log|
          error = nil
          begin
            filters_hash = log.respond_to?(:filters_hash) ? log.filters_hash : {}
            error = filters_hash["error"] || filters_hash[:error]
          rescue StandardError
            error = nil
          end

          {
            id: log.id,
            query: log.query,
            search_type: log.search_type,
            execution_time_ms: log.execution_time_ms,
            results_count: log.results_count,
            created_at: log.created_at,
            error: error
          }
        end
    rescue StandardError => e
      @logger.error "Error fetching search logs: #{e.message}"
      []
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

    def topic_payload(topic)
      tag_names = ::SmartRAG::Models::Tag
                  .join(:research_topic_tags, tag_id: :id)
                  .where(research_topic_id: topic.id)
                  .select_map(:name)

      document_ids = ::SmartRAG::Models::SourceSection
                     .join(:research_topic_sections, section_id: :id)
                     .where(research_topic_id: topic.id)
                     .exclude(document_id: nil)
                     .distinct
                     .select_map(:document_id)

      document_count = ::SmartRAG::Models::SourceSection
                       .join(:research_topic_sections, section_id: :id)
                       .where(research_topic_id: topic.id)
                       .exclude(document_id: nil)
                       .distinct
                       .count(:document_id)

      {
        id: topic.id,
        topic_id: topic.id,
        title: topic.name,
        description: topic.description,
        tags: tag_names.uniq,
        document_ids: document_ids,
        document_count: document_count,
        created_at: topic.created_at,
        updated_at: topic.respond_to?(:updated_at) ? topic.updated_at : topic.created_at
      }
    end

    def vector_error_response(query, options, error_message)
      {
        query: query,
        results: [],
        search_type: :vector,
        total_results: 0,
        metadata: {
          total_count: 0,
          execution_time_ms: 0,
          language: options[:language] || :en,
          error: error_message
        }
      }
    end

    def fulltext_error_response(query, options, error_message)
      {
        query: query,
        results: {
          results: [],
          metadata: {
            total_count: 0,
            execution_time_ms: 0,
            language: options[:language] || :en,
            error: error_message
          }
        },
        search_type: :fulltext
      }
    end

    def hybrid_error_response(query, options, error_message)
      {
        query: query,
        results: [],
        metadata: {
          total_count: 0,
          execution_time_ms: 0,
          language: options[:language] || :en,
          alpha: options[:alpha] || 0.7,
          text_result_count: 0,
          vector_result_count: 0,
          multilingual: false,
          error: error_message
        }
      }
    end
  end
end
