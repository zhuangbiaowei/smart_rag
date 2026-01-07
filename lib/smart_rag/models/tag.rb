require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # Tag model for categorizing document sections
    class Tag < Sequel::Model
      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:tags)
      end
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps, update_on_create: false  # Only created_at

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Relationships
      many_to_one :parent, class: '::SmartRAG::Models::Tag', key: :parent_id
      one_to_many :children, class: '::SmartRAG::Models::Tag', key: :parent_id
      many_to_many :sections, class: '::SmartRAG::Models::SourceSection',
                   join_table: :section_tags,
                   left_key: :tag_id,
                   right_key: :section_id
      one_to_many :section_tags, class: '::SmartRAG::Models::SectionTag', key: :tag_id
      one_to_many :research_topic_tags, class: '::SmartRAG::Models::ResearchTopicTag', key: :tag_id
      many_to_many :research_topics, class: '::SmartRAG::Models::ResearchTopic',
                   join_table: :research_topic_tags,
                   left_key: :tag_id,
                   right_key: :research_topic_id

      # Validation
      def validate
        super
        validates_presence :name
        validates_unique :name
        validates_max_length 255, :name
        validates_integer :parent_id, allow_nil: true
      end

      # Class methods
      class << self
        # Find tag by name
        def find_by_name(name)
          where(name: name).first
        end

        # Find or create tag by name
        # This method supports both:
        #   find_or_create("tag_name") - positional
        #   find_or_create(name: "tag_name") - keyword
        #   find_or_create(name: "tag_name", parent_id: 1) - keyword with parent
        def find_or_create(name_or_attrs = nil, **kwargs)
          # Handle keyword arguments (when called as find_or_create(name: "..."))
          if kwargs.any? || name_or_attrs.nil?
            name = kwargs[:name] || name_or_attrs
            parent_id = kwargs[:parent_id]
          else
            # Handle positional argument (when called as find_or_create("..."))
            name = name_or_attrs
            parent_id = nil
          end

          find_by_name(name) || create(name: name, parent_id: parent_id)
        end

        # Get all root tags (no parent)
        def root_tags
          where(parent_id: nil).all
        end

        # Get tag hierarchy
        def hierarchy
          root_tags.map { |tag| build_hierarchy(tag) }
        end

        # Build hierarchy for a tag
        def build_hierarchy(tag)
          {
            id: tag.id,
            name: tag.name,
            children: tag.children.map { |child| build_hierarchy(child) }
          }
        end

        # Search tags by name
        def search(query)
          where(Sequel.like(:name, "%#{query}%")).all
        end

        # Get popular tags (most used)
        def popular(limit: 20)
          db[:tags]
            .select(:tags__id, :tags__name, Sequel.function(:count, :section_tags__id).as(:usage_count))
            .left_join(:section_tags, tag_id: :id)
            .group(:tags__id, :tags__name)
            .order(Sequel.desc(:usage_count))
            .limit(limit)
            .map { |row| { id: row[:id], name: row[:name], usage_count: row[:usage_count] } }
        end

        # Get tags with section count
        def with_section_count
          select(Sequel[:tags].*).select_append(Sequel.function(:count, :section_tags__id).as(:section_count))
            .left_join(:section_tags, tag_id: :id)
            .group(:tags__id)
            .order(Sequel.desc(:section_count))
        end

        # Batch create tags
        def batch_create(tag_names, parent_id: nil)
          db.transaction do
            tag_names.map { |name| find_or_create(name, parent_id: parent_id) }
          end
        end
      end

      # Instance methods

      # Get full path of tag (with ancestors)
      def full_path
        path = [self]
        current = self
        while current.parent
          path.unshift(current.parent)
          current = current.parent
        end
        path
      end

      # Get path as string
      def path_string(separator: ' > ')
        full_path.map(&:name).join(separator)
      end

      # Check if tag has children
      def has_children?
        !children.empty?
      end

      # Check if tag is root (no parent)
      def root?
        parent_id.nil?
      end

      # Get all descendant tags
      def descendants
        results = []
        children.each do |child|
          results << child
          results.concat(child.descendants)
        end
        results
      end

      # Get all ancestor tags
      def ancestors
        return [] if root?
        parent.ancestors + [parent]
      end

      # Add section to tag
      def add_section(section)
        super(section) unless sections.include?(section)
      end

      # Remove section from tag
      def remove_section(section)
        super(section) if sections.include?(section)
      end

      # Count sections with this tag
      def section_count
        sections.count
      end

      # Move tag to new parent
      def move_to(new_parent_id)
        return if new_parent_id == parent_id

        # Check for circular reference
        if new_parent_id == id || descendants.map(&:id).include?(new_parent_id)
          raise ArgumentError, "Cannot move tag: would create circular reference"
        end

        update(parent_id: new_parent_id)
      end

      # Tag info hash
      def info
        {
          id: id,
          name: name,
          parent_id: parent_id,
          path: path_string,
          has_children: has_children?,
          is_root: root?,
          section_count: section_count,
          created_at: created_at
        }
      end

      # String representation
      def to_s
        "<Tag: #{id} - #{name}#{parent_id ? ' (child)' : ' (root)'}>"
      end
    end
  end
end