require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # SourceSection model representing document chunks/sections
    class SourceSection < Sequel::Model
      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:source_sections)
      end
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
      many_to_one :document, class: '::SmartRAG::Models::SourceDocument', key: :document_id
      one_to_one :embedding, class: '::SmartRAG::Models::Embedding', key: :source_id
      one_to_one :section_fts, class: '::SmartRAG::Models::SectionFts', key: :section_id
      one_to_many :section_tags, class: '::SmartRAG::Models::SectionTag', key: :section_id
      many_to_many :tags, class: '::SmartRAG::Models::Tag',
                   join_table: :section_tags,
                   left_key: :section_id,
                   right_key: :tag_id
      one_to_many :research_topic_sections, class: '::SmartRAG::Models::ResearchTopicSection', key: :section_id
      many_to_many :research_topics, class: '::SmartRAG::Models::ResearchTopic',
                   join_table: :research_topic_sections,
                   left_key: :section_id,
                   right_key: :research_topic_id

      # Validation
      def validate
        super
        validates_presence [:document_id, :content]
        validates_presence :section_title, allow_nil: true
        validates_integer :section_number, allow_nil: true
      end

      # Class methods
      class << self
        # Find sections by document
        def by_document(document_id)
          where(document_id: document_id)
        end

        # Search sections by content
        def search_content(query)
          where(Sequel.like(:content, "%#{query}%"))
        end

        # Search sections by title
        def search_title(query)
          where(Sequel.like(:section_title, "%#{query}%"))
        end

        # Get sections by section number range
        def by_section_number_range(min, max)
          where(section_number: min..max)
        end

        # Count sections per document
        def count_per_document
          group_and_count(:document_id).all
        end

        # Get sections without embeddings
        def without_embeddings(limit: 100)
          where(Sequel.lit(
            "id NOT IN (SELECT source_id FROM embeddings)"
          )).limit(limit)
        end

        # Get sections with embeddings
        def with_embeddings
          association_join(:embedding)
        end

        # Recently created sections
        def recent(limit: 50)
          order(Sequel.desc(:created_at)).limit(limit)
        end

        # Find by section title
        def find_by_title(title)
          where(section_title: title).first
        end

        # Batch insert sections
        def batch_insert(sections)
          db.transaction do
            dataset.multi_insert(sections)
          end
        end

        # Get sections for vector search (with embeddings)
        def for_vector_search
          association_join(:embedding).eager(:document)
        end

        # Get total content size by document
        def content_size_by_document
          select(:document_id, Sequel.function(:sum, Sequel.function(:length, :content)).as(:total_size))
            .group(:document_id)
        end
      end

      # Instance methods

      # Get word count
      def word_count
        content.to_s.split.size
      end

      # Get character count
      def character_count
        content.to_s.length
      end

      # Check if section has embedding
      def has_embedding?
        !embedding.nil?
      end

      # Check if section has FTS
      def has_fts?
        !section_fts.nil?
      end

      # Get section summary
      def summary(max_length: 200)
        content.to_s.truncate(max_length)
      end

      # Get section preview (first part)
      def preview(length: 100)
        content.to_s[0...length]
      end

      # Get tags as array of names
      def tag_names
        tags.map(&:name)
      end

      # Add a tag
      def add_tag(tag)
        super(tag) unless tags.include?(tag)
      end

      # Remove a tag
      def remove_tag(tag)
        super(tag) if tags.include?(tag)
      end

      # Find similar sections (by content or embedding)
      def find_similar(limit: 5)
        if has_embedding? && embedding.vector
          # Use vector similarity
          Embedding.similar_to(embedding.vector_array, limit: limit)
            .map { |emb| emb.section }
            .compact
        else
          # Fallback to text similarity search
          SourceSection.search_content(content.to_s[0..100])
            .where.not(id: id)
            .limit(limit)
            .all
        end
      end

      # Section info hash
      def info
        {
          id: id,
          document_id: document_id,
          section_title: section_title,
          section_number: section_number,
          word_count: word_count,
          character_count: character_count,
          has_embedding: has_embedding?,
          has_fts: has_fts?,
          tag_count: tags.count,
          created_at: created_at,
          updated_at: updated_at,
          preview: preview
        }
      end

      # String representation
      def to_s
        "<SourceSection: #{id} - #{section_title || 'Untitled'} (#{word_count} words)>"
      end
    end
  end
end