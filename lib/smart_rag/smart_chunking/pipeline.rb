require_relative "parser"
require_relative "structure_detector"
require_relative "merger"
require_relative "tokenizer"
require_relative "media_context"

module SmartRAG
  module SmartChunking
    class Pipeline
      def initialize(token_limit: 400)
        @tokenizer = Tokenizer.new
        @detector = StructureDetector.new
        @merger = Merger.new(tokenizer: @tokenizer, token_limit: token_limit)
        @media_context = MediaContext.new
      end

      def chunk(content, doc_type: :general, options: {})
        sections = Parser.new.parse(content)
        return [] if sections.empty?

        chunks = case doc_type
                 when :laws
                   @merger.tree_merge(sections, depth: 2)
                 when :book
                   @merger.hierarchical_merge(sections, depth: 5)
                 when :paper, :manual
                   pivot, = @detector.title_frequency(sections)
                   @merger.merge_by_pivot(sections, pivot)
                 else
                   @merger.naive_merge(sections)
                 end

        chunks = @media_context.attach(chunks, options)

        chunks.map do |chunk|
          {
            title: chunk.title,
            content: chunk.content,
            metadata: chunk.metadata || {}
          }
        end
      end
    end
  end
end
