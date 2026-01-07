require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # SectionFts model for full-text search optimization
    class SectionFts < Sequel::Model(:section_fts)
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps, update_on_create: true

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Relationships
      many_to_one :section, class: '::SmartRAG::Models::SourceSection', key: :section_id
      many_to_one :document, class: '::SmartRAG::Models::SourceDocument', key: :document_id

      # Validation
      def validate
        super
        validates_presence :section_id
        validates_presence :language, allow_nil: true
        validates_format /\A[a-z]{2}\z/, :language, allow_nil: true, message: 'must be ISO 639-1 code'
      end

      # Class methods
      class << self
        # Full-text search using tsvector
        def search(query, language: nil, fields: [:fts_combined], limit: 20)
          # Ensure we have valid fields
          valid_fields = [:fts_title, :fts_content, :fts_combined]
          fields = Array(fields) & valid_fields

          # Build the tsquery
          tsquery = build_tsquery(query, language || 'simple')

          # Build the search query
          search_conditions = fields.map do |field|
            Sequel.lit("#{field} @@ #{tsquery}")
          end

          # Union of all field searches (OR condition)
          where(Sequel.|(*search_conditions))
            .order(Sequel.desc(Sequel.lit("ts_rank(#{fields.join(' || ')}, #{tsquery})")))
            .limit(limit)
        end

        # Find by document
        def by_document(document_id)
          where(document_id: document_id)
        end

        # Find by section
        def by_section(section_id)
          where(section_id: section_id)
        end

        # Find by language
        def by_language(lang)
          where(language: lang)
        end

        # Custom ranking search
        def search_with_ranking(query, language: nil, weights: '1.0, 0.5, 0.2', limit: 20)
          tsquery = build_tsquery(query, language || 'simple')

          select(:*,
                 Sequel.lit("ts_rank('{#{weights}}', fts_combined, #{tsquery})").as(:rank))
            .where(Sequel.lit("fts_combined @@ #{tsquery}"))
            .order(Sequel.desc(:rank))
            .limit(limit)
        end

        # Build tsquery from text
        def build_tsquery(query, language = 'simple')
          # Convert query to tsquery format
          # Replace spaces with & for AND search
          # Add * for prefix matching
          terms = query.to_s.split.map { |term| "#{term}:*" }
          terms.join(' & ')
        end

        # Find sections with fresh FTS data
        def fresh(max_age: 3600)
          # Sections updated within the last hour
          where(Sequel.lit('updated_at > ?', Time.now - max_age))
        end

        # Find stale FTS entries
        def stale
          # Find sections without FTS or with old FTS
          subquery = db[:source_sections]
                     .left_join(:section_fts, section_id: :id)
                     .where(Sequel.|(
                       { Sequel[:section_fts][:section_id] => nil },
                       Sequel.lit('source_sections.updated_at > section_fts.updated_at')
                     ))
                     .select(:source_sections__id)

          where(section_id: subquery)
        end

        # Create or update FTS entry
        def create_or_update(section_id, attrs)
          existing = find(section_id: section_id)
          if existing
            existing.update(attrs)
            existing
          else
            create(attrs.merge(section_id: section_id))
          end
        end
      end

      # Instance methods

      # Check if FTS data is up to date with section
      def up_to_date?(section_updated_at)
        return false unless updated_at
        updated_at >= section_updated_at
      end

      # Get search vectors as hash
      def vectors
        {
          title: fts_title,
          content: fts_content,
          combined: fts_combined
        }
      end

      # Update search vectors
      def update_vectors(title_vector, content_vector, combined_vector)
        update(
          fts_title: title_vector,
          fts_content: content_vector,
          fts_combined: combined_vector,
          updated_at: Time.now
        )
      end

      # Get rank for a query
      def rank_for(query, language: nil, weights: '1.0, 0.5, 0.2')
        tsquery = self.class.build_tsquery(query, language || 'simple')
        db[Sequel.lit("SELECT ts_rank('{#{weights}}', ?, ?) as rank", fts_combined, tsquery)].first[:rank]
      end

      # Section FTS info
      def info
        {
          section_id: section_id,
          document_id: document_id,
          language: language,
          has_vectors: fts_combined.present?,
          updated_at: updated_at
        }
      end

      # String representation
      def to_s
        "<SectionFts: section_id=#{section_id}>"
      end
    end
  end
end
