require_relative "smart_rag/version"
require_relative "smart_rag/config"
require_relative "smart_rag/errors"
require_relative "smart_rag/models"
require_relative "smart_rag/retrieve"
require "sequel"
require "logger"
require "digest"
require "json"

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

    # Structured retrieval interface for SmartBrain integration.
    # @param plan [Hash] RetrievalPlan object
    # @return [Hash] EvidencePack
    def retrieve(plan:)
      @retrieve_executor ||= ::SmartRAG::Retrieve.new(self)
      @retrieve_executor.execute(plan: plan)
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

    # Rebuild full-text indexes for all sections or a single document.
    def rebuild_fts(document_id = nil)
      manager = query_processor&.fulltext_search_service&.fulltext_manager
      return { success: false, indexed_sections: 0, failed_sections: 0, error: 'Fulltext manager unavailable' } unless manager

      sections = sections_scope(document_id)
      result = { success: true, indexed_sections: 0, failed_sections: 0, errors: [] }

      sections.each do |section|
        language = section.document&.language || "en"
        ok = manager.update_fulltext_index(section.id, section.section_title.to_s, section.content.to_s, language)
        if ok
          result[:indexed_sections] += 1
        else
          result[:failed_sections] += 1
          result[:success] = false
          result[:errors] << { section_id: section.id, error: "FTS update failed" }
        end
      end

      result
    rescue StandardError => e
      @logger.error "Failed to rebuild FTS index: #{e.message}"
      { success: false, indexed_sections: 0, failed_sections: 0, error: e.message }
    end

    # Rebuild embeddings for all sections or a single document.
    def rebuild_embeddings(document_id = nil)
      service = query_processor&.embedding_service
      return { success: false, rebuilt_embeddings: 0, failed_sections: 0, error: 'Embedding service unavailable' } unless service

      sections = sections_scope(document_id)
      result = { success: true, rebuilt_embeddings: 0, failed_sections: 0, errors: [] }

      sections.each do |section|
        ::SmartRAG::Models::Embedding.delete_by_section(section.id)
        service.generate_for_section(section)
        result[:rebuilt_embeddings] += 1
      rescue StandardError => e
        result[:failed_sections] += 1
        result[:success] = false
        result[:errors] << { section_id: section.id, error: e.message }
      end

      result
    rescue StandardError => e
      @logger.error "Failed to rebuild embeddings: #{e.message}"
      { success: false, rebuilt_embeddings: 0, failed_sections: 0, error: e.message }
    end

    # Rebuild both FTS and embeddings.
    def reindex(document_id = nil)
      fts = rebuild_fts(document_id)
      embeddings = rebuild_embeddings(document_id)

      {
        success: fts[:success] && embeddings[:success],
        fts: fts,
        embeddings: embeddings
      }
    end

    # Dedupe documents by source_uri + content_hash.
    # Keeps the earliest document in each duplicate group.
    def dedupe_by_content_hash
      docs = ::SmartRAG::Models::SourceDocument.all
      by_key = Hash.new { |h, k| h[k] = [] }

      docs.each do |doc|
        hash = document_content_hash(doc)
        source_uri = document_source_uri(doc)
        next if hash.nil? || hash.empty?
        next if source_uri.nil? || source_uri.empty?

        by_key["#{source_uri}|#{hash}"] << doc
      end

      deleted = 0
      groups = 0
      by_key.each_value do |group|
        next if group.length <= 1

        groups += 1
        keeper = group.min_by { |d| d.created_at || Time.at(0) }
        group.each do |doc|
          next if doc.id == keeper.id

          remove_document(doc.id)
          deleted += 1
        end
      end

      { success: true, deduped_groups: groups, deleted_documents: deleted }
    rescue StandardError => e
      @logger.error "Failed to dedupe by content hash: #{e.message}"
      { success: false, deduped_groups: 0, deleted_documents: 0, error: e.message }
    end

    # Backfill source_uri/source_type/content_hash for existing documents.
    def backfill_source_fields(limit: nil, dry_run: false)
      docs = ::SmartRAG::Models::SourceDocument.dataset
      docs = docs.limit(limit.to_i) if limit && limit.to_i > 0
      docs = docs.all

      updated = 0
      skipped = 0
      errors = []

      docs.each do |doc|
        source_uri = document_source_uri(doc)
        source_type = infer_source_type_from_uri(source_uri)
        content_hash = document_content_hash(doc)

        if (doc.respond_to?(:source_uri) && doc.source_uri.to_s == source_uri.to_s) &&
           (doc.respond_to?(:source_type) && doc.source_type.to_s == source_type.to_s) &&
           (doc.respond_to?(:content_hash) && doc.content_hash.to_s == content_hash.to_s)
          skipped += 1
          next
        end

        unless dry_run
          payload = {}
          payload[:source_uri] = source_uri if doc.respond_to?(:source_uri)
          payload[:source_type] = source_type if doc.respond_to?(:source_type)
          payload[:content_hash] = content_hash if doc.respond_to?(:content_hash)
          doc.update(payload) unless payload.empty?
        end
        updated += 1
      rescue StandardError => e
        errors << { document_id: doc.respond_to?(:id) ? doc.id : nil, error: e.message }
      end

      {
        success: errors.empty?,
        dry_run: dry_run,
        total_documents: docs.length,
        updated_documents: updated,
        skipped_documents: skipped,
        errors: errors
      }
    rescue StandardError => e
      @logger.error "Failed to backfill source fields: #{e.message}"
      {
        success: false,
        dry_run: dry_run,
        total_documents: 0,
        updated_documents: 0,
        skipped_documents: 0,
        errors: [{ error: e.message }]
      }
    end

    # One-shot release preparation pipeline.
    # Steps: backfill source fields -> dedupe -> reindex
    def prepare_release_indexes(document_id: nil, dry_run: false)
      backfill = backfill_source_fields(dry_run: dry_run)
      dedupe = dry_run ? { success: true, dry_run: true, deduped_groups: 0, deleted_documents: 0 } : dedupe_by_content_hash
      reindex_result = dry_run ? { success: true, dry_run: true } : reindex(document_id)

      {
        success: backfill[:success] && dedupe[:success] && reindex_result[:success],
        backfill: backfill,
        dedupe: dedupe,
        reindex: reindex_result
      }
    rescue StandardError => e
      @logger.error "Failed to prepare release indexes: #{e.message}"
      {
        success: false,
        backfill: { success: false },
        dedupe: { success: false },
        reindex: { success: false },
        error: e.message
      }
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

    def sections_scope(document_id)
      dataset = ::SmartRAG::Models::SourceSection.dataset
      if !document_id.nil?
        return [] unless document_id.to_s =~ /\A-?\d+\Z/

        dataset = dataset.where(document_id: document_id.to_i)
      end

      dataset.eager(:document).all
    end

    def document_content_hash(document)
      existing_hash = if document.respond_to?(:content_hash)
                        document.content_hash
                      else
                        nil
                      end
      return existing_hash if existing_hash && !existing_hash.to_s.empty?

      metadata = parse_document_metadata(document)
      metadata_hash = metadata["content_hash"] || metadata[:content_hash]
      return metadata_hash if metadata_hash && !metadata_hash.to_s.empty?

      content = ::SmartRAG::Models::SourceSection.where(document_id: document.id).order(:id).select_map(:content).join("\n")
      return nil if content.empty?

      content_hash = Digest::SHA256.hexdigest(content)
      metadata["content_hash"] = content_hash

      update_payload = { metadata: metadata }
      update_payload[:content_hash] = content_hash if document.respond_to?(:content_hash)
      document.update(update_payload)
      content_hash
    rescue StandardError => e
      @logger.warn "Failed to compute content hash for document #{document.id}: #{e.message}"
      nil
    end

    def document_source_uri(document)
      source_uri = if document.respond_to?(:source_uri)
                     document.source_uri
                   else
                     nil
                   end
      return source_uri if source_uri && !source_uri.to_s.empty?

      metadata = parse_document_metadata(document)
      metadata_source = metadata["source_uri"] || metadata[:source_uri]
      return metadata_source if metadata_source && !metadata_source.to_s.empty?

      document.respond_to?(:url) ? document.url : nil
    rescue StandardError
      nil
    end

    def infer_source_type_from_uri(source_uri)
      uri = source_uri.to_s
      return "url" if uri.start_with?("http://", "https://")
      return "file" if uri.start_with?("file://", "/")

      "manual"
    end

    def parse_document_metadata(document)
      metadata = document.metadata
      if metadata.is_a?(String)
        metadata = JSON.parse(metadata) rescue {}
      end
      metadata.is_a?(Hash) ? metadata : {}
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
