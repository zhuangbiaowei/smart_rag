require 'sequel'

module SmartRAG
  module Models
    # Load the base model class first (sets up delayed connection)
    require_relative 'models/model_base'

    # Track whether models have been loaded
    @models_loaded = false

    class << self
      attr_reader :models_loaded

      # Load all model classes
      def load_models!
        return if @models_loaded
        @models_loaded = true

        # Require all model files
        require_relative 'models/embedding'
        require_relative 'models/source_document'
        require_relative 'models/source_section'
        require_relative 'models/tag'
        require_relative 'models/section_fts'
        require_relative 'models/text_search_config'
        require_relative 'models/research_topic'
        require_relative 'models/section_tag'
        require_relative 'models/research_topic_section'
        require_relative 'models/research_topic_tag'
        require_relative 'models/search_log'
      end
    end

    # Set database for all models
    def self.db=(db_connection)
      @db = db_connection
      ::SmartRAG.db = db_connection
      Sequel::Model.db = db_connection

      # Load models if not already loaded
      load_models! unless @models_loaded

      # Initialize each model as a Sequel::Model subclass
      [Embedding, SourceDocument, SourceSection, Tag, SectionFts,
       TextSearchConfig, ResearchTopic, SectionTag,
       ResearchTopicSection, ResearchTopicTag, SearchLog].each do |model|
        model.set_dataset_from_db if model.respond_to?(:set_dataset_from_db)
      end
    end

    def self.db
      @db || ::SmartRAG.db
    end

    # Auto migrate all models (create tables if they don't exist)
    def self.auto_migrate!
      # Run migrations from db/migrations directory
      db.extension :migration
      migrations_dir = File.expand_path('../../db/migrations', __dir__)

      if Dir.exist?(migrations_dir)
        Sequel::Migrator.run(db, migrations_dir)
      end
    end

    # Clear all data (use with caution)
    def self.truncate_all!
      tables = db.tables
      tables.each do |table|
        db[table].truncate :cascade
      end
    end

    # Get model statistics
    def self.statistics
      {
        documents: SourceDocument.count,
        sections: SourceSection.count,
        tags: Tag.count,
        embeddings: Embedding.count,
        research_topics: ResearchTopic.count,
        search_logs: SearchLog.count
      }
    end

    # Find model by table name
    def self.model_for_table(table_name)
      case table_name.to_sym
      when :embeddings
        Embedding
      when :source_documents
        SourceDocument
      when :source_sections
        SourceSection
      when :tags
        Tag
      when :section_fts
        SectionFts
      when :text_search_configs
        TextSearchConfig
      when :research_topics
        ResearchTopic
      when :section_tags
        SectionTag
      when :research_topic_sections
        ResearchTopicSection
      when :research_topic_tags
        ResearchTopicTag
      when :search_logs
        SearchLog
      else
        nil
      end
    end
  end
end
