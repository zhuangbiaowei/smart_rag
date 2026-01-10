require_relative '../models/text_search_config'

module SmartRAG
  module Parsers
    # Query parser for full-text search queries
    # Handles language detection and tsquery building
    class QueryParser
      # Language patterns for detection
      LANGUAGE_PATTERNS = {
        'zh' => /[\u4e00-\u9fff]/, # Chinese characters
        'ja' => /[\u3040-\u309f\u30a0-\u30ff]/, # Japanese hiragana/katakana
        'ko' => /[\uac00-\ud7af]/, # Korean hangul
        'en' => /[a-zA-Z]/ # English letters
      }.freeze

      # Advanced query operators
      ADVANCED_OPERATORS = %w[AND OR NOT ""].freeze

      def initialize
        @logger = Logger.new(STDOUT)
      end

      # Detect language of the given text
      # @param text [String] Text to analyze
      # @return [String] Language code (en/zh/ja/ko/default)
      def detect_language(text)
        return 'en' if text.nil? || text.strip.empty?

        text = text.strip
        char_counts = {}

        # Count characters for each language
        LANGUAGE_PATTERNS.each do |lang, pattern|
          count = text.scan(pattern).length
          char_counts[lang] = count if count > 0
        end

        # Return the language with most characters
        # If no clear winner, default to 'en'
        if char_counts.empty?
          'en'
        else
          char_counts.max_by { |_, count| count }[0]
        end
      rescue StandardError => e
        @logger.error "Language detection failed: #{e.message}"
        'en' # Default to English on error
      end

      # Build tsquery from text query
      # @param text [String] Search query text
      # @param language [String] Language code
      # @return [String] tsquery string
      def build_tsquery(text, language = 'en')
        raise ArgumentError, 'Query text cannot be nil' if text.nil?
        raise ArgumentError, 'Query text cannot be empty' if text.strip.empty?

        @logger.debug "QueryParser.build_tsquery called with text='#{text}', language='#{language}' (class: #{language.class})"

        # Detect query type and build appropriate tsquery
        if advanced_query?(text)
          build_advanced_tsquery(text, language)
        elsif phrase_query?(text)
          build_phrase_tsquery(text, language)
        else
          build_plain_tsquery(text, language)
        end
      rescue StandardError => e
        @logger.error "Failed to build tsquery: #{e.message}"
        raise Errors::QueryParseError, "Failed to parse query: #{e.message}"
      end

      # Parse advanced query with operators
      # @param text [String] Query text with operators
      # @return [Hash] Parsed query structure
      def parse_advanced_query(text)
        raise ArgumentError, 'Query text cannot be nil' if text.nil?
        raise ArgumentError, 'Query text cannot be empty' if text.strip.empty?

        # Remove extra whitespace
        text = text.strip

        # Parse quoted phrases
        phrases = extract_quoted_phrases(text)

        # Parse boolean operators
        tokens = tokenize_query(text)

        {
          original: text,
          tokens: tokens,
          phrases: phrases,
          has_boolean: tokens.any? { |t| %w[AND OR NOT].include?(t[:type]) },
          has_phrases: phrases.any?
        }
      rescue StandardError => e
        @logger.error "Advanced query parsing failed: #{e.message}"
        {
          original: text || '',
          tokens: [{ type: 'text', value: text || '' }],
          phrases: [],
          has_boolean: false,
          has_phrases: false
        }
      end

      private

      # Check if query contains advanced operators
      def advanced_query?(text)
        # Check for boolean operators (case insensitive)
        return true if text =~ /\b(AND|OR|NOT)\b/i

        # Check for quotes
        return true if text.include?('"')

        false
      end

      # Check if query is a phrase query (wrapped in quotes)
      def phrase_query?(text)
        text.strip.start_with?('"') && text.strip.end_with?('"')
      end

      # Build tsquery for natural language queries
      def build_plain_tsquery(text, language)
        # Get text search configuration for language
        config = get_text_search_config(language)

        # Use plainto_tsquery for single-term queries
        terms = text.strip.split(/\s+/).reject(&:empty?)
        return "plainto_tsquery('#{config}', #{escape_quote(text)})" if terms.length <= 1

        # For multi-term queries, use OR to avoid overly strict matching
        joined = terms.map { |term| "plainto_tsquery('#{config}', #{escape_quote(term)})" }
                      .join(' || ')
        "(#{joined})"
      end

      # Build tsquery for phrase queries
      def build_phrase_tsquery(text, language)
        config = get_text_search_config(language)

        # Remove quotes and use phraseto_tsquery for phrase queries
        phrase = text.strip[1...-1] # Remove surrounding quotes
        "phraseto_tsquery('#{config}', #{escape_quote(phrase)})"
      end

      # Build tsquery for advanced queries with operators
      def build_advanced_tsquery(text, language)
        config = get_text_search_config(language)
        parsed = parse_advanced_query(text)

        # Convert parsed query to tsquery format
        if parsed[:has_phrases] || parsed[:has_boolean]
          build_complex_tsquery(parsed, config)
        else
          build_plain_tsquery(text, language)
        end
      end

      # Build complex tsquery from parsed structure
      def build_complex_tsquery(parsed, config)
        # This is a simplified implementation
        # In production, you might want more sophisticated parsing
        query_parts = []

        # Process phrases first
        parsed[:phrases].each do |phrase|
          query_parts << "phraseto_tsquery('#{config}', #{escape_quote(phrase)})"
        end

        # Process tokens - handle NOT as unary operator
        # "a NOT b" should become "a & !b"
        tokens = parsed[:tokens].dup
        until tokens.empty?
          token = tokens.shift
          case token[:type]
          when 'text'
            query_parts << "plainto_tsquery('#{config}', #{escape_quote(token[:value])})"
          when 'AND'
            query_parts << '&&'
          when 'OR'
            query_parts << '||'
          when 'NOT'
            # NOT is unary - add & before it and apply to next token
            query_parts << '&&' if !query_parts.last.to_s.include?('&&') && !query_parts.last.to_s.empty?
            query_parts << '!!'
            # Next token should be text, we need to negate it
            next_token = tokens.shift
            if next_token && next_token[:type] == 'text'
              query_parts << "plainto_tsquery('#{config}', #{escape_quote(next_token[:value])})"
            end
          end
        end

        # Wrap in parentheses to ensure proper precedence and type handling
        operators = ['&&', '||', '!!']
        normalized = []
        query_parts.each do |part|
          next if part.to_s.strip.empty?

          if operators.include?(part)
            normalized << part
            next
          end

          if normalized.any?
            prev = normalized.last
            if !operators.include?(prev)
              normalized << '&&'
            end
          end

          normalized << part
        end

        while normalized.any? && operators.include?(normalized.last)
          normalized.pop
        end

        return "plainto_tsquery('#{config}', #{escape_quote(parsed[:original])})" if normalized.empty?

        query_expr = normalized.join(' ')
        "(#{query_expr})::tsquery"
      end

      # Extract quoted phrases from text
      def extract_quoted_phrases(text)
        phrases = []
        # Match quoted strings, handling escaped quotes
        text.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/).each do |match|
          phrases << match[0].gsub('\\"', '"') # Unescape quotes
        end
        phrases
      end

      # Tokenize query into operators and text
      def tokenize_query(text)
        tokens = []

        # Remove quoted phrases first
        without_quotes = text.gsub(/"[^"]*"/, 'PHRASE_PLACEHOLDER')

        # Split by operators
        parts = without_quotes.split(/\b(AND|OR|NOT)\b/i)

        parts.each_with_index do |part, _index|
          part = part.strip
          next if part.empty?

          if part =~ /^(AND|OR|NOT)$/i
            tokens << { type: part.upcase, value: part.upcase }
          elsif part == 'PHRASE_PLACEHOLDER'
            # Skip placeholders (phrases handled separately)
            next
          else
            tokens << { type: 'text', value: part }
          end
        end

        tokens
      end

      # Get text search configuration for language
      def get_text_search_config(language)
        # Try to get config from database
        config = Models::TextSearchConfig.first(language_code: language.to_s)
        return config.config_name if config

        # Fallback to simple config
        'pg_catalog.simple'
      rescue StandardError => e
        @logger.error "Failed to get text search config: #{e.message}"
        'pg_catalog.simple'
      end

      # Escape single quotes for SQL
      def escape_quote(text)
        "'" + text.gsub("'", "''") + "'"
      end
    end

    # Custom error for query parsing
    module Errors
      class QueryParseError < StandardError; end
    end
  end
end
