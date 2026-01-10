module SmartRAG
  module SmartChunking
    class Tokenizer
      def initialize(multiplier: 0.25)
        @multiplier = multiplier
      end

      def estimate_tokens(text)
        return 0 if text.nil? || text.empty?

        ascii = text.scan(/[[:ascii:]]/).length
        non_ascii = text.length - ascii
        words = text.scan(/[A-Za-z0-9_]+/).length

        base = (ascii * @multiplier).ceil
        base + non_ascii + words
      end

      def token_count_for_chunk(chunk)
        estimate_tokens(chunk.content.to_s)
      end
    end
  end
end
