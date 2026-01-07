require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # ResearchTopicTag model for many-to-many relationship between topics and tags
    class ResearchTopicTag < Sequel::Model(:research_topic_tags)
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps, update_on_create: false
      # Allow mass assignment of composite primary key
      unrestrict_primary_key

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Relationships
      many_to_one :research_topic, class: '::SmartRAG::Models::ResearchTopic', key: :research_topic_id
      many_to_one :tag, class: '::SmartRAG::Models::Tag', key: :tag_id

      # Validation
      def validate
        super
        validates_presence [:research_topic_id, :tag_id]
        validates_unique [:research_topic_id, :tag_id]
      end

      # Class methods
      class << self
        # Find by topic and tag
        def find_by_topic_and_tag(topic_id, tag_id)
          where(research_topic_id: topic_id, tag_id: tag_id).first
        end

        # Get all tags for a topic
        def tags_for_topic(topic_id)
          where(research_topic_id: topic_id).all
        end

        # Get all topics for a tag
        def topics_for_tag(tag_id)
          where(tag_id: tag_id).all
        end

        # Delete all tags for a topic
        def delete_all_for_topic(topic_id)
          where(research_topic_id: topic_id).delete
        end

        # Delete all topics for a tag
        def delete_all_for_tag(tag_id)
          where(tag_id: tag_id).delete
        end

        # Bulk create associations
        def bulk_create(associations)
          db.transaction do
            dataset.multi_insert(associations)
          end
        end

        # Check if topic has a specific tag
        def has_tag?(topic_id, tag_id)
          where(research_topic_id: topic_id, tag_id: tag_id).count > 0
        end

        # Get popular tags for topics
        def popular_tags(limit: 20)
          db[:research_topic_tags]
            .select(:tag_id, Sequel.function(:count, :research_topic_id).as(:topic_count))
            .group(:tag_id)
            .order(Sequel.desc(:topic_count))
            .limit(limit)
        end
      end

      # Instance methods

      # String representation
      def to_s
        "<ResearchTopicTag: topic:#{research_topic_id} => tag:#{tag_id}>"
      end
    end
  end
end
