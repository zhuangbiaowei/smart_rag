require_relative "chunk"

module SmartRAG
  module SmartChunking
    class Merger
      def initialize(tokenizer:, token_limit: 400)
        @tokenizer = tokenizer
        @token_limit = token_limit
      end

      def naive_merge(sections)
        chunks = []
        current = nil

        sections.each do |section|
          next if section.text.to_s.strip.empty?

          candidate = build_content(current, section)
          if current.nil?
            current = Chunk.new(
              title: section.title,
              content: candidate,
              metadata: { levels: [section.level].compact }
            )
            next
          end

          if @tokenizer.estimate_tokens(candidate) <= @token_limit
            current.content = candidate
            current.metadata[:levels] << section.level if section.level
          else
            chunks << current
            current = Chunk.new(
              title: section.title,
              content: section.text,
              metadata: { levels: [section.level].compact }
            )
          end
        end

        chunks << current if current
        chunks
      end

      def hierarchical_merge(sections, depth: 5)
        grouped = []
        current_group = []

        sections.each do |section|
          if section.level && section.level <= depth && current_group.any?
            grouped << current_group
            current_group = []
          end
          current_group << section
        end
        grouped << current_group if current_group.any?

        grouped.flat_map { |group| naive_merge(group) }
      end

      def tree_merge(sections, depth: 2)
        hierarchical_merge(sections, depth: depth)
      end

      def merge_by_pivot(sections, pivot_level)
        return naive_merge(sections) if pivot_level.nil?

        grouped = []
        current_group = []

        sections.each do |section|
          if section.level && section.level <= pivot_level && current_group.any?
            grouped << current_group
            current_group = []
          end
          current_group << section
        end
        grouped << current_group if current_group.any?

        grouped.flat_map { |group| naive_merge(group) }
      end

      private

      def build_content(current, section)
        if current.nil?
          section.text
        else
          [current.content, section.text].join("\n\n")
        end
      end
    end
  end
end
