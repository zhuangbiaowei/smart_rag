require "spec_helper"
require "smart_rag/parsers/query_parser"

RSpec.describe SmartRAG::Parsers::QueryParser do
  let(:query_parser) { described_class.new }

  describe "#detect_language" do
    it "detects Chinese text" do
      text = "这是一个中文文本"
      expect(query_parser.detect_language(text)).to eq("zh")
    end

    it "detects English text" do
      text = "This is an English text"
      expect(query_parser.detect_language(text)).to eq("en")
    end

    it "detects Japanese text" do
      text = "これは日本語のテキストです"
      expect(query_parser.detect_language(text)).to eq("ja")
    end

    it "detects Korean text" do
      text = "이것은 한국어 텍스트입니다"
      expect(query_parser.detect_language(text)).to eq("ko")
    end

    it "defaults to English for empty text" do
      expect(query_parser.detect_language("")).to eq("en")
      expect(query_parser.detect_language(nil)).to eq("en")
      expect(query_parser.detect_language("   ")).to eq("en")
    end

    it "detects language with mixed content" do
      # Text with more Chinese characters
      text = "这是一个mixed text的例子，包含了很多中文字符"
      expect(query_parser.detect_language(text)).to eq("zh")

      # Text with more English
      text = "This is an example of mixed text that contains many English words"
      expect(query_parser.detect_language(text)).to eq("en")
    end
  end

  describe "#build_tsquery" do
    it "raises error for nil query" do
      expect { query_parser.build_tsquery(nil, "en") }.to raise_error(SmartRAG::Parsers::Errors::QueryParseError, /Query text cannot be nil/)
    end

    it "raises error for empty query" do
      expect { query_parser.build_tsquery("", "en") }.to raise_error(SmartRAG::Parsers::Errors::QueryParseError, /Query text cannot be empty/)
      expect { query_parser.build_tsquery("   ", "en") }.to raise_error(SmartRAG::Parsers::Errors::QueryParseError, /Query text cannot be empty/)
    end

    it "builds tsquery for natural language queries" do
      query = "machine learning algorithms"
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("plainto_tsquery")
      expect(tsquery).to include("machine learning algorithms")
      expect(tsquery).to include("pg_catalog.english")
    end

    it "builds tsquery for phrase queries" do
      query = '"neural networks"'
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("phraseto_tsquery")
      expect(tsquery).to include("neural networks")
    end

    it "builds tsquery for Chinese queries" do
      query = "机器学习"
      tsquery = query_parser.build_tsquery(query, "zh")

      expect(tsquery).to include("plainto_tsquery")
      expect(tsquery).to include("jieba")
    end

    it "builds tsquery for advanced queries with AND" do
      query = "machine AND learning"
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("&&")
    end

    it "builds tsquery for advanced queries with OR" do
      query = "machine OR learning"
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("||")
    end

    it "builds tsquery for advanced queries with NOT" do
      query = "machine NOT learning"
      tsquery = query_parser.build_tsquery(query, "en")

      # In tsquery syntax, !! is the unary NOT operator
      expect(tsquery).to include("!!")
      expect(tsquery).to include("&&")  # NOT in boolean search means AND NOT
    end

    it "handles complex queries with multiple operators" do
      query = '"neural networks" AND (deep OR machine) NOT python'
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("phraseto_tsquery")
    end

    it "escapes single quotes in queries" do
      query = "can't"
      tsquery = query_parser.build_tsquery(query, "en")

      expect(tsquery).to include("''") # SQL escaped quotes
    end

    it "raises QueryParseError on build failure" do
      allow(query_parser).to receive(:get_text_search_config).and_raise(StandardError.new("DB error"))

      expect do
        query_parser.build_tsquery("test", "en")
      end.to raise_error(SmartRAG::Parsers::Errors::QueryParseError)
    end
  end

  describe "#parse_advanced_query" do
    it "parses simple text queries" do
      query = "machine learning"
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:original]).to eq("machine learning")
      expect(parsed[:has_boolean]).to be false
      expect(parsed[:has_phrases]).to be false
      expect(parsed[:phrases]).to be_empty
      expect(parsed[:tokens].length).to eq(1)
      expect(parsed[:tokens].first[:type]).to eq("text")
    end

    it "identifies boolean operators" do
      query = "machine AND learning"
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_boolean]).to be true
      expect(parsed[:tokens].length).to eq(3)
      expect(parsed[:tokens][1][:type]).to eq("AND")
    end

    it "detects OR operator" do
      query = "machine OR learning"
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_boolean]).to be true
      expect(parsed[:tokens].any? { |t| t[:type] == "OR" }).to be true
    end

    it "detects NOT operator" do
      query = "machine NOT learning"
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_boolean]).to be true
      expect(parsed[:tokens].any? { |t| t[:type] == "NOT" }).to be true
    end

    it "extracts quoted phrases" do
      query = '"neural networks" are important'
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_phrases]).to be true
      expect(parsed[:phrases]).to include("neural networks")
    end

    it "handles multiple quoted phrases" do
      query = '"neural networks" AND "deep learning"'
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_phrases]).to be true
      expect(parsed[:phrases]).to include("neural networks", "deep learning")
      expect(parsed[:has_boolean]).to be true
    end

    it "handles escaped quotes in phrases" do
      query = '"can\\"t stop" learning'
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:phrases]).to include('can"t stop')
    end

    it "handles complex queries" do
      query = '"neural networks" AND (deep OR machine) NOT "supervised learning"'
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_phrases]).to be true
      expect(parsed[:has_boolean]).to be true
      expect(parsed[:phrases]).to include("neural networks", "supervised learning")
    end

    it "handles queries with only operators" do
      query = "AND OR NOT"
      parsed = query_parser.parse_advanced_query(query)

      expect(parsed[:has_boolean]).to be true
      expect(parsed[:tokens].length).to eq(3)
    end

    it "returns fallback result for nil query" do
      result = query_parser.parse_advanced_query(nil)
      expect(result[:original]).to eq("")
      expect(result[:tokens].first[:value]).to eq("")
    end

    it "returns fallback result for empty query" do
      result = query_parser.parse_advanced_query("")
      expect(result[:original]).to eq("")
      expect(result[:tokens].first[:value]).to eq("")
    end

    it "handles parsing failures gracefully" do
      # This should return a valid structure even on error
      allow(query_parser).to receive(:tokenize_query).and_raise(StandardError.new("Parse error"))

      result = query_parser.parse_advanced_query("test")

      expect(result[:original]).to eq("test")
      expect(result[:tokens]).not_to be_empty
      expect(result[:phrases]).to be_empty
      expect(result[:has_boolean]).to be false
      expect(result[:has_phrases]).to be false
    end
  end

  describe "private methods" do
    describe "#advanced_query?" do
      it "detects AND operator" do
        expect(query_parser.send(:advanced_query?, "machine AND learning")).to be true
      end

      it "detects OR operator" do
        expect(query_parser.send(:advanced_query?, "machine OR learning")).to be true
      end

      it "detects NOT operator" do
        expect(query_parser.send(:advanced_query?, "machine NOT learning")).to be true
      end

      it "detects quoted queries" do
        expect(query_parser.send(:advanced_query?, '"neural networks"')).to be true
      end

      it "returns false for simple queries" do
        expect(query_parser.send(:advanced_query?, "machine learning")).to be false
      end

      it "detects case-insensitive operators" do
        expect(query_parser.send(:advanced_query?, "machine and learning")).to be true
        expect(query_parser.send(:advanced_query?, "machine And learning")).to be true
        expect(query_parser.send(:advanced_query?, "machine AND learning")).to be true
      end
    end

    describe "#phrase_query?" do
      it "detects phrase queries" do
        expect(query_parser.send(:phrase_query?, '"neural networks"')).to be true
      end

      it "returns false for non-quoted text" do
        expect(query_parser.send(:phrase_query?, "neural networks")).to be false
      end

      it "returns false for unbalanced quotes" do
        expect(query_parser.send(:phrase_query?, '"neural networks')).to be false
        expect(query_parser.send(:phrase_query?, 'neural networks"')).to be false
      end
    end

    describe "#extract_quoted_phrases" do
      it "extracts single phrase" do
        text = 'This is a "neural network" example'
        phrases = query_parser.send(:extract_quoted_phrases, text)

        expect(phrases).to include("neural network")
      end

      it "extracts multiple phrases" do
        text = '"deep learning" and "neural networks" are important'
        phrases = query_parser.send(:extract_quoted_phrases, text)

        expect(phrases).to include("deep learning", "neural networks")
      end

      it "handles empty text" do
        expect(query_parser.send(:extract_quoted_phrases, "")).to be_empty
      end

      it "handles text without quotes" do
        text = "This has no quoted phrases"
        expect(query_parser.send(:extract_quoted_phrases, text)).to be_empty
      end

      it "handles escaped quotes" do
        text = '"can\\"t stop" learning'
        phrases = query_parser.send(:extract_quoted_phrases, text)

        expect(phrases).to include('can"t stop')
      end
    end

    describe "#tokenize_query" do
      it "tokenizes simple text" do
        tokens = query_parser.send(:tokenize_query, "machine learning")

        expect(tokens.length).to eq(1)
        expect(tokens.first[:type]).to eq("text")
        expect(tokens.first[:value]).to eq("machine learning")
      end

      it "tokenizes with AND operator" do
        tokens = query_parser.send(:tokenize_query, "machine AND learning")

        expect(tokens.length).to eq(3)
        expect(tokens[0][:type]).to eq("text")
        expect(tokens[1][:type]).to eq("AND")
        expect(tokens[2][:type]).to eq("text")
      end

      it "tokenizes with multiple operators" do
        tokens = query_parser.send(:tokenize_query, "deep OR machine AND learning")

        expect(tokens.length).to eq(5)
        expect(tokens[1][:type]).to eq("OR")
        expect(tokens[3][:type]).to eq("AND")
      end

      it "skips phrase placeholders" do
        # After extracting phrases, they become placeholders
        text = 'Text with "phrase" inside'
        tokens = query_parser.send(:tokenize_query, text)

        # Should only have the non-phrase text
        expect(tokens.all? { |t| t[:value] != "PHRASE_PLACEHOLDER" }).to be true
      end
    end

    describe "#escape_quote" do
      it "escapes single quotes" do
        escaped = query_parser.send(:escape_quote, "can't")
        expect(escaped).to eq("'can''t'")
      end

      it "wraps text in quotes" do
        escaped = query_parser.send(:escape_quote, "test")
        expect(escaped).to eq("'test'")
      end

      it "handles multiple quotes" do
        escaped = query_parser.send(:escape_quote, "don't can't won't")
        expect(escaped).to eq("'don''t can''t won''t'")
      end
    end
  end
end
