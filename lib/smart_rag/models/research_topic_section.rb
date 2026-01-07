require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # ResearchTopicSection model for many-to-many relationship
    class ResearchTopicSection < Sequel::Model(:research_topic_sections)
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps, update_on_create: false

      # Allow mass assignment of primary keys
      unrestrict_primary_key

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Relationships
      many_to_one :research_topic, class: '::SmartRAG::Models::ResearchTopic', key: :research_topic_id
      many_to_one :section, class: '::SmartRAG::Models::SourceSection', key: :section_id

      # Validation
      def validate
        super
        validates_presence [:research_topic_id, :section_id]
        validates_unique [:research_topic_id, :section_id]
      end

      # Class methods
      class << self
        # Find by topic and section
        def find_by_topic_and_section(topic_id, section_id)
          where(research_topic_id: topic_id, section_id: section_id).first
        end

        # Get all sections for a topic
        def sections_for_topic(topic_id)
          where(research_topic_id: topic_id).all
        end

        # Get all topics for a section
        def topics_for_section(section_id)
          where(section_id: section_id).all
        end

        # Delete all sections for a topic
        def delete_all_for_topic(topic_id)
          where(research_topic_id: topic_id).delete
        end

        # Delete all topics for a section
        def delete_all_for_section(section_id)
          where(section_id: section_id).delete
        end

        # Bulk create associations
        def bulk_create(associations)
          db.transaction do
            dataset.multi_insert(associations)
          end
        end

        # Check if section belongs to topic
        def in_topic?(topic_id, section_id)
          where(research_topic_id: topic_id, section_id: section_id).count > 0
        end

        # Get recent associations
        def recent(limit: 50)
          order(Sequel.desc(:created_at)).limit(limit)
        end
      end

      # Instance methods

      # String representation
      def to_s
        "<ResearchTopicSection: topic:#{research_topic_id} => section:#{section_id}>"
      end
    end
  end
end
