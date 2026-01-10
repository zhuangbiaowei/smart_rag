require_relative "section"

module SmartRAG
  module SmartChunking
    class Parser
      HEADING_PATTERN = /^(#+)\s+(.+)$/.freeze

      def parse(content)
        return [] if content.nil? || content.empty?

        content = content.sub(/\A\uFEFF/, '')
        lines = content.lines
        sections = []

        current_title = nil
        current_level = nil
        buffer = []
        intro_buffer = []
        first_heading_seen = false

        lines.each do |line|
          if (match = line.match(HEADING_PATTERN))
            heading_level = match[1].length
            heading_title = match[2].strip

            if !first_heading_seen
              first_heading_seen = true
              current_title = heading_title
              current_level = heading_level
              intro_text = intro_buffer.join.strip
              if intro_text.length > 0
                sections << Section.new(
                  title: current_title,
                  text: intro_text,
                  level: current_level,
                  layout: "head"
                )
              end
            else
              flush_section(sections, current_title, current_level, buffer)
              current_title = heading_title
              current_level = heading_level
            end

            buffer = []
            next
          end

          if !first_heading_seen
            intro_buffer << line
          else
            buffer << line
          end
        end

        flush_section(sections, current_title, current_level, buffer)
        sections
      end

      private

      def flush_section(sections, title, level, buffer)
        text = buffer.join.strip
        return if title.nil? || text.empty?

        sections << Section.new(
          title: title,
          text: text,
          level: level,
          layout: "text"
        )
      end
    end
  end
end
