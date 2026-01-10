module SmartRAG
  module SmartChunking
    class StructureDetector
      BULLET_PATTERN = /
        ^\s*(
          [-*+]\s+|
          \d+[.)]\s+|
          [一二三四五六七八九十]+[、.]\s+
        )
      /x.freeze

      def bullets_category(sections)
        hits = 0
        sections.each do |section|
          next if section.text.to_s.empty?
          hits += 1 if section.text.match?(BULLET_PATTERN)
        end
        hits
      end

      def title_frequency(sections)
        levels = sections.map(&:level).compact
        return [nil, []] if levels.empty?

        freq = levels.tally
        pivot = freq.max_by { |_level, count| count }&.first
        [pivot, levels]
      end
    end
  end
end
