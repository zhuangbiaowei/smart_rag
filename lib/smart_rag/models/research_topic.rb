require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # ResearchTopic model for organizing content by topics
    class ResearchTopic < Sequel::Model
      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:research_topics)
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
      one_to_many :research_topic_sections, class: '::SmartRAG::Models::ResearchTopicSection', key: :research_topic_id
      one_to_many :research_topic_tags, class: '::SmartRAG::Models::ResearchTopicTag', key: :research_topic_id
      many_to_many :sections, class: '::SmartRAG::Models::SourceSection',
                   join_table: :research_topic_sections,
                   left_key: :research_topic_id,
                   right_key: :section_id
      many_to_many :tags, class: '::SmartRAG::Models::Tag',
                   join_table: :research_topic_tags,
                   left_key: :research_topic_id,
                   right_key: :tag_id

      # Validation
      def validate
        super
        validates_presence :name
        validates_max_length 500, :name
        validates_presence :description, allow_nil: true
      end

      # Class methods
      class << self
        # Find topic by name
        def find_by_name(name)
          where(Sequel.ilike(:name, name)).first
        end

        # Search topics by name or description
        def search(query)
          where(Sequel.ilike(:name, "%#{query}%"))
            .or(Sequel.ilike(:description, "%#{query}%"))
        end

        # Get topics with section count
        def with_section_count
          select(Sequel[:research_topics].*).select_append(Sequel.function(:count, :research_topic_sections__section_id).as(:section_count))
            .left_join(:research_topic_sections, research_topic_id: :id)
            .group(:research_topics__id)
            .order(Sequel.desc(:section_count))
        end

        # Get topics by tag
        def by_tag(tag_id)
          where(id: db[:research_topic_tags].select(:research_topic_id).where(tag_id: tag_id))
        end

        # Get recently used topics
        def recent(limit: 10)
          order(Sequel.desc(:created_at)).limit(limit)
        end

        # Batch create topics
        def batch_create(topics)
          db.transaction do
            topics.map { |topic_data| create(topic_data) }
          end
        end
      end

      # Instance methods

      # Add section to topic
      def add_section(section)
        unless sections.include?(section)
          self.add_section(section)
        end
      end

      # Remove section from topic
      def remove_section(section)
        if sections.include?(section)
          self.remove_section(section)
        end
      end

      # Add tag to topic
      def add_tag(tag)
        unless tags.include?(tag)
          self.add_tag(tag)
        end
      end

      # Remove tag from topic
      def remove_tag(tag)
        if tags.include?(tag)
          self.remove_tag(tag)
        end
      end

      # Count sections for this topic
      def section_count
        sections.count
      end

      # Count tags for this topic
      def tag_count
        tags.count
      end

      # Get related topics (share sections or tags)
      def related_topics(limit: 5)
        topic_ids = db[:research_topic_sections]
                    .select(:research_topic_id)
                    .where(section_id: sections.map(&:id))
                    .where.not(research_topic_id: id)
                    .group(:research_topic_id)
                    .order(Sequel.desc(Sequel.function(:count, :*)))
                    .limit(limit)

        self.class.where(id: topic_ids).all
      end

      # Get topics info
      def info
        {
          id: id,
          name: name,
          section_count: section_count,
          tag_count: tag_count,
          created_at: created_at
        }
      end

      # String representation
      def to_s
        "<ResearchTopic: #{id} - #{name} (#{section_count} sections, #{tag_count} tags)>"
      end

      # Alias name as title for API compatibility
      def title
        name
      end

      def title=(value)
        self.name = value
      end

      # Alias created_at as updated_at for API compatibility
      def updated_at
        @updated_at || created_at
      end

      # Allow updated_at= for API compatibility (stored in memory only, not DB)
      def updated_at=(value)
        @updated_at = value
      end
    end
  end
end
