require "smart_prompt"
require_relative "../errors"

module SmartRAG
  module Services
    # Service for generating natural language summaries and responses
    class SummarizationService
      attr_reader :config, :logger, :smart_prompt_engine

      # Initialize the summarization service
      # @param config [Hash] Configuration options
      # @option config [String] :config_path Path to smart_prompt config (default: config/llm_config.yml)
      # @option config [Integer] :max_retries Maximum retries for API calls (default: 3)
      # @option config [Integer] :timeout Timeout for API calls (default: 30)
      # @option config [Logger] :logger Logger instance (default: Logger.new(STDOUT))
      # @option config [Integer] :max_context_length Maximum context length (default: 4000)
      def initialize(config = {})
        config ||= {}
        @logger = Logger.new(STDOUT)
        @config = default_config.merge(config)
        @logger = @config[:logger] || @logger
        @max_context_length = @config[:max_context_length]

        # Load workers
        workers_dir = File.join(File.dirname(__FILE__), '..', '..', '..', 'workers')
        Dir.glob(File.join(workers_dir, '*.rb')).each { |file| require file }

        # Initialize SmartPrompt engine
        config_path = @config[:config_path] || "config/llm_config.yml"
        @smart_prompt_engine = SmartPrompt::Engine.new(config_path)

        @logger.info "SummarizationService initialized"
      rescue StandardError => e
        log_error("Failed to initialize SummarizationService", e)
        raise
      end

      # Summarize search results into a coherent answer
      # @param question [String] The original question
      # @param context [String] Search results context
      # @param options [Hash] Summarization options
      # @option options [Symbol] :language Output language (:zh_cn, :zh_tw, :en, :ja)
      # @option options [Integer] :max_length Maximum response length (default: 1000)
      # @option options [String] :tone Response tone (formal, casual, technical)
      # @option options [Boolean] :include_citations Whether to include citations (default: true)
      # @return [Hash] Summarized response with answer and metadata
      def summarize_search_results(question, context, options = {})
        raise ArgumentError, "Question cannot be nil or empty" if question.to_s.strip.empty?
        raise ArgumentError, "Context cannot be nil" if context.nil?

        logger.info "Summarizing search results for question: #{question[0..50]}..."
        logger.info "Context length: #{context.length} chars"

        # Truncate context if too long
        truncated_context = truncate_context(context)
        language = options[:language] || :en
        max_length = options[:max_length] || 1000
        tone = options[:tone] || 'formal'

        # Build prompt based on language
        prompt = build_summarization_prompt(
          question,
          truncated_context,
          language,
          max_length,
          tone,
          options
        )

        # Call LLM to generate summary
        response = call_llm_for_summary(prompt, options)

        # Parse response
        parsed_response = parse_summary_response(response, options)

        logger.info "Successfully generated summary (#{parsed_response[:answer].length} chars), confidence: #{parsed_response[:confidence]}"

        parsed_response
      rescue ArgumentError
        raise
      rescue StandardError => e
        log_error("Failed to summarize search results", e)
        raise ::SmartRAG::Errors::SummarizationServiceError, "Summarization failed: #{e.message}"
      end

      # Generate a standalone summary of a text
      # @param text [String] Text to summarize
      # @param options [Hash] Summarization options
      # @return [String] Summary text
      def summarize_text(text, options = {})
        raise ArgumentError, "Text cannot be nil or empty" if text.to_s.strip.empty?

        logger.info "Summarizing text (#{text.length} chars)..."

        language = options[:language] || detect_language(text)
        max_length = options[:max_length] || 500

        prompt = build_standalone_summary_prompt(text, language, max_length)
        response = call_llm_for_summary(prompt, options)

        summary = extract_text_from_response(response)
        logger.info "Generated summary (#{summary.length} chars)"

        summary
      rescue ArgumentError
        raise
      rescue StandardError => e
        log_error("Failed to summarize text", e)
        raise ::SmartRAG::Errors::SummarizationServiceError, "Text summarization failed: #{e.message}"
      end

      private

      def build_summarization_prompt(question, context, language, max_length, tone, options)
        include_citations = options.fetch(:include_citations, true)

        case language
        when :zh_cn
          build_chinese_summarization_prompt(question, context, max_length, tone, include_citations)
        when :zh_tw
          build_traditional_chinese_summarization_prompt(question, context, max_length, tone, include_citations)
        when :en
          build_english_summarization_prompt(question, context, max_length, tone, include_citations)
        when :ja
          build_japanese_summarization_prompt(question, context, max_length, tone, include_citations)
        else
          logger.warn "Unsupported language: #{language}, defaulting to English"
          build_english_summarization_prompt(question, context, max_length, tone, include_citations)
        end
      end

      def build_chinese_summarization_prompt(question, context, max_length, tone, include_citations)
        prompt = "基于以下搜索结果，回答问题并提供详细解释。"
        prompt << "\n\n问题：#{question}\n\n"
        prompt << "搜索结果：\n#{context}\n\n"
        prompt << "要求：\n"
        prompt << "1. 提供直接、准确的答案\n"
        prompt << "2. 使用搜索结果中的信息支持你的回答\n"
        prompt << "3. 答案长度不超过#{max_length}个字符\n"
        prompt << "4. 语气：#{tone == 'formal' ? '正式' : tone == 'casual' ? '随意' : '专业'}\n"
        prompt << "5. #{include_citations ? '使用[1]、[2]等格式引用来源' : '不需要引用来源'}\n\n"
        prompt << "请提供结构化的回答：\n"
        prompt << "- 简要答案（1-2句话）\n"
        prompt << "- 详细解释\n"
        include_citations ? (prompt << "- 来源引用\n") : ""
        prompt << "\n以JSON格式输出：{\"answer\": \"...\", \"confidence\": 0.0-1.0}"
      end

      def build_traditional_chinese_summarization_prompt(question, context, max_length, tone, include_citations)
        prompt = "基於以下搜尋結果，回答問題並提供詳細解釋。"
        prompt << "\n\n問題：#{question}\n\n"
        prompt << "搜尋結果：\n#{context}\n\n"
        prompt << "要求：\n"
        prompt << "1. 提供直接、準確的答案\n"
        prompt << "2. 使用搜尋結果中的資訊支持你的回答\n"
        prompt << "3. 答案長度不超過#{max_length}個字元\n"
        prompt << "4. 語氣：#{tone == 'formal' ? '正式' : tone == 'casual' ? '隨意' : '專業'}\n"
        prompt << "5. #{include_citations ? '使用[1]、[2]等格式引用來源' : '不需要引用來源'}\n\n"
        prompt << "請提供結構化的回答：\n"
        prompt << "- 簡要答案（1-2句話）\n"
        prompt << "- 詳細解釋\n"
        include_citations ? (prompt << "- 來源引用\n") : ""
        prompt << "\n以JSON格式輸出：{\"answer\": \"...\", \"confidence\": 0.0-1.0}"
      end

      def build_english_summarization_prompt(question, context, max_length, tone, include_citations)
        prompt = "Based on the following search results, answer the question and provide detailed explanation."
        prompt << "\n\nQuestion: #{question}\n\n"
        prompt << "Search Results:\n#{context}\n\n"
        prompt << "Requirements:\n"
        prompt << "1. Provide a direct, accurate answer\n"
        prompt << "2. Support your answer with information from the search results\n"
        prompt << "3. Keep answer under #{max_length} characters\n"
        prompt << "4. Tone: #{tone}\n"
        prompt << "5. #{include_citations ? 'Cite sources using [1], [2] format' : 'No citations needed'}\n\n"
        prompt << "Provide a structured response:\n"
        prompt << "- Brief answer (1-2 sentences)\n"
        prompt << "- Detailed explanation\n"
        include_citations ? (prompt << "- Source citations\n") : ""
        prompt << "\nOutput in JSON format: {\"answer\": \"...\", \"confidence\": 0.0-1.0}"
      end

      def build_japanese_summarization_prompt(question, context, max_length, tone, include_citations)
        prompt = "以下の検索結果に基づいて、質問に答えて詳細な説明を提供してください。"
        prompt << "\n\n質問：#{question}\n\n"
        prompt << "検索結果：\n#{context}\n\n"
        prompt << "要件：\n"
        prompt << "1. 直接的で正確な答えを提供する\n"
        prompt << "2. 検索結果の情報を使用して回答をサポートする\n"
        prompt << "3. 回答は#{max_length}文字以内にする\n"
        prompt << "4. トーン：#{tone == 'formal' ? 'フォーマル' : tone == 'casual' ? 'カジュアル' : '専門的'}\n"
        prompt << "5. #{include_citations ? '[1]、[2]などの形式で情報源を引用' : '引用は不要'}\n\n"
        prompt << "構造化された回答を提供：\n"
        prompt << "- 簡潔な答え（1-2文）\n"
        prompt << "- 詳細な説明\n"
        include_citations ? (prompt << "- 情報源の引用\n") : ""
        prompt << "\nJSON形式で出力：{\"answer\": \"...\", \"confidence\": 0.0-1.0}"
      end

      def build_standalone_summary_prompt(text, language, max_length)
        case language
        when :zh_cn
          "用#{max_length}字以内的简洁中文总结以下内容：\n\n#{text}"
        when :zh_tw
          "用#{max_length}字以內的簡潔繁體中文總結以下內容：\n\n#{text}"
        when :en
          "Summarize the following content in English within #{max_length} characters:\n\n#{text}"
        when :ja
          "次の内容を日本語で#{max_length}文字以内に要約してください：\n\n#{text}"
        else
          "Summarize the following content within #{max_length} characters:\n\n#{text}"
        end
      end

      def call_llm_for_summary(prompt, options = {})
        max_retries = options[:retries] || config[:max_retries]
        timeout = options[:timeout] || config[:timeout]

        with_retry(max_retries: max_retries, timeout: timeout) do
          result = smart_prompt_engine.call_worker(:generate_content, { content: prompt })
          raise "No response from LLM" unless result
          result
        end
      rescue StandardError => e
        logger.error "LLM call for summarization failed: #{e.message}"
        raise
      end

      def parse_summary_response(response, options = {})
        # Try to parse as JSON first
        if response =~ /\{.*answer.*confidence.*\}/m
          begin
            parsed = JSON.parse(response.gsub(/```json\n?|\n?```/, ''))
            return {
              answer: parsed["answer"] || parsed["response"] || response,
              confidence: parsed["confidence"]&.to_f || 0.8,
              raw_response: response
            }
          rescue JSON::ParserError
            logger.warn "Failed to parse JSON response, using raw response"
          end
        end

        # Fallback to using the entire response as answer
        {
          answer: response,
          confidence: 0.8, # Default confidence
          raw_response: response
        }
      end

      def extract_text_from_response(response)
        # Remove any JSON wrapper if present
        if response =~ /\{.*answer.*\}/m
          begin
            parsed = JSON.parse(response.gsub(/```json\n?|\n?```/, ''))
            return parsed["answer"] || parsed["response"] || response
          rescue JSON::ParserError
            # Continue to fallback
          end
        end

        # Remove markdown code blocks
        response.gsub(/```[a-z]*\n?|\n?```/, '').strip
      end

      def truncate_context(context)
        return context if context.length <= max_context_length

        logger.warn "Context too long (#{context.length} chars), truncating to #{max_context_length}"
        context[0...max_context_length] + "... (truncated)"
      end

      def detect_language(text)
        # Check for Japanese hiragana/katakana first (more specific than Chinese kanji)
        return :ja if text.match?(/[\u3040-\u309f\u30a0-\u30ff]/)
        return :zh_cn if text.match?(/[\u4e00-\u9fff]/)
        :en
      end

      def max_context_length
        @max_context_length
      end

      def with_retry(max_retries:, timeout:, &block)
        last_exception = nil

        max_retries.times do |attempt|
          begin
            Timeout.timeout(timeout) do
              return yield
            end
          rescue StandardError => e
            last_exception = e
            logger.warn "Attempt #{attempt + 1} failed: #{e.message}"

            # Exponential backoff
            sleep(2  ** attempt) if attempt < max_retries - 1
          end
        end

        raise last_exception
      end

      def log_error(message, exception)
        active_logger = logger || @logger || Logger.new(STDOUT)
        active_logger.error "#{message}: #{exception.message}"
        active_logger.error exception.backtrace.join("\n  ")
      end

      def default_config
        {
          config_path: "config/llm_config.yml",
          max_retries: 3,
          timeout: 30,
          max_context_length: 4000,
          logger: Logger.new(STDOUT)
        }
      end
    end
  end
end
