require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # Source document model representing original documents
    class SourceDocument < Sequel::Model
      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:source_documents)
      end
      plugin :validation_helpers
      plugin :timestamps, update_on_create: true
      include FactoryBotHelpers

      # Constants
      DOWNLOAD_STATES = {
        pending: 0,
        completed: 1,
        failed: 2
      }.freeze

      # Relationships
      one_to_many :sections, class: '::SmartRAG::Models::SourceSection', key: :document_id
      one_to_many :section_fts, class: '::SmartRAG::Models::SectionFts', key: :document_id
      one_to_many :section_tags, class: '::SmartRAG::Models::SectionTag', key: :section_id

      # Validation
      def validate
        super
        validates_presence :title
        validates_integer :download_state, allow_nil: true
        validates_includes DOWNLOAD_STATES.values, :download_state, allow_nil: true
        validates_format /\A[a-z]{2}\z/, :language, allow_nil: true, message: 'must be ISO 639-1 code'
      end

      # Class methods
      class << self
        # Find documents by download state
        def by_download_state(state)
          where(download_state: state)
        end

        # Find completed documents
        def completed
          by_download_state(DOWNLOAD_STATES[:completed])
        end

        # Find pending documents
        def pending
          by_download_state(DOWNLOAD_STATES[:pending])
        end

        # Find failed documents
        def failed
          by_download_state(DOWNLOAD_STATES[:failed])
        end

        # Find documents by language
        def by_language(lang)
          where(language: lang)
        end

        # Search documents by title or description
        def search(query)
          where(Sequel.like(:title, "%#{query}%"))
            .or(Sequel.like(:description, "%#{query}%"))
        end

        # Order by publication date
        def order_by_publication_date(direction = :desc)
          order(Sequel.send(direction, :publication_date))
        end

        # Recent documents
        def recent(days: 30)
          where(Sequel.lit('publication_date >= ?', Date.today - days))
        end

        # Delete old documents and their sections
        def delete_old_documents(days: 90)
          cutoff_date = Time.now - (days * 24 * 60 * 60)

          db.transaction do
            # Delete related embeddings
            db[:embeddings].where(source_id: db[:source_sections].select(:id).where(document_id: db.from(:source_documents).where(Sequel.lit('created_at < ?', cutoff_date)).select(:id))).delete

            # Delete section FTS
            db[:section_fts].where(document_id: db.from(:source_documents).where(Sequel.lit('created_at < ?', cutoff_date)).select(:id)).delete

            # Delete sections
            db[:source_sections].where(document_id: db.from(:source_documents).where(Sequel.lit('created_at < ?', cutoff_date)).select(:id)).delete

            # Delete documents
            where(Sequel.lit('created_at < ?', cutoff_date)).delete
          end
        end

        # Create or update document
        def create_or_update(attributes)
          if existing = find_by_url(attributes[:url])
            existing.update(attributes)
            existing
          else
            create(attributes)
          end
        end

        # Find by URL
        def find_by_url(url)
          where(url: url).first
        end

        # Find by multiple fields
        def find_by_criteria(criteria)
          query = self
          criteria.each do |field, value|
            query = query.where(field => value)
          end
          query.all
        end

        # Batch insert documents
        def batch_insert(documents)
          db.transaction do
            dataset.multi_insert(documents)
          end
        end

        # Update download state
        def update_download_state(id, state)
          where(id: id).update(download_state: state, updated_at: Time.now)
        end
      end

      # Instance methods

      # Check if document is completed
      def completed?
        download_state == DOWNLOAD_STATES[:completed]
      end

      # Check if document is pending
      def pending?
        download_state == DOWNLOAD_STATES[:pending]
      end

      # Check if document is failed
      def failed?
        download_state == DOWNLOAD_STATES[:failed]
      end

      # Set download state
      def set_download_state(state)
        update(download_state: DOWNLOAD_STATES[state])
      end

      # Get all sections with their embeddings
      def sections_with_embeddings
        sections.eager(:embedding).all
      end

      # Count sections
      def section_count
        sections.count
      end

      # Get document info hash
      def info
        {
          id: id,
          title: title,
          url: url,
          author: author,
          publication_date: publication_date,
          language: language,
          description: description,
          download_state: download_state,
          section_count: section_count,
          created_at: created_at,
          updated_at: updated_at
        }
      end

      # String representation
      def to_s
        "<SourceDocument: #{id} - #{title}>"
      end
    end
  end
end
