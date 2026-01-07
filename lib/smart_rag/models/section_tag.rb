require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # SectionTag model for many-to-many relationship between sections and tags
    class SectionTag < Sequel::Model(:section_tags)
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

      # Relationships (explicit, though many_to_many is used in main models)
      many_to_one :section, class: '::SmartRAG::Models::SourceSection', key: :section_id
      many_to_one :tag, class: '::SmartRAG::Models::Tag', key: :tag_id

      # Validation
      def validate
        super
        validates_presence [:section_id, :tag_id]
        validates_unique [:section_id, :tag_id]
      end

      # Class methods
      class << self
        # Find by section and tag
        def find_by_section_and_tag(section_id, tag_id)
          where(section_id: section_id, tag_id: tag_id).first
        end

        # Get all tags for a section
        def tags_for_section(section_id)
          where(section_id: section_id).all
        end

        # Get all sections for a tag
        def sections_for_tag(tag_id)
          where(tag_id: tag_id).all
        end

        # Delete all tags for a section
        def delete_all_for_section(section_id)
          where(section_id: section_id).delete
        end

        # Delete all sections for a tag
        def delete_all_for_tag(tag_id)
          where(tag_id: tag_id).delete
        end

        # Bulk create associations
        def bulk_create(associations)
          db.transaction do
            dataset.multi_insert(associations)
          end
        end

        # Check if section has a specific tag
        def has_tag?(section_id, tag_id)
          where(section_id: section_id, tag_id: tag_id).count > 0
        end
      end

      # Instance methods

      # String representation
      def to_s
        "<SectionTag: section:#{section_id} => tag:#{tag_id}>"
      end
    end
  end
end
