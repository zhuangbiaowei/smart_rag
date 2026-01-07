require "spec_helper"
require "smart_rag/services/summarization_service"

RSpec.describe SmartRAG::Services::SummarizationService do
  let(:config) { { logger: Logger.new(nil) } }
  let(:service) { described_class.new(config) }

  let(:mock_smart_prompt_engine) { instance_double("SmartPrompt::Engine") }

  before do
    allow(SmartPrompt::Engine).to receive(:new).and_return(mock_smart_prompt_engine)
  end

  describe "#initialize" do
    it "initializes with default config" do
      expect(service).to be_a(described_class)
    end

    it "initializes with custom config" do
      custom_config = {
        max_retries: 5,
        timeout: 60,
        max_context_length: 8000
      }
      custom_service = described_class.new(custom_config)
      expect(custom_service).to be_a(described_class)
    end
  end

  describe "#summarize_search_results" do
    let(:question) { "What is machine learning?" }
    let(:context) { "Machine learning is a subset of AI. It enables computers to learn from data." }

    context "in English" do
      let(:llm_response) do
        {
          "answer" => "Machine learning is a subset of AI that enables computers to learn from data without explicit programming.",
          "confidence" => 0.92
        }.to_json
      end

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(llm_response)
      end

      it "generates a summary from search results" do
        result = service.summarize_search_results(question, context, language: :en)

        expect(result).to have_key(:answer)
        expect(result).to have_key(:confidence)
        expect(result[:answer]).to be_a(String)
        expect(result[:confidence]).to be_a(Float)
        expect(result[:confidence]).to be_between(0.0, 1.0)
      end

      it "validates question is not nil" do
        expect {
          service.summarize_search_results(nil, context)
        }.to raise_error(ArgumentError, /Question cannot be nil/)
      end

      it "validates question is not empty" do
        expect {
          service.summarize_search_results("", context)
        }.to raise_error(ArgumentError, /Question cannot be nil/)
      end

      it "validates context is not nil" do
        expect {
          service.summarize_search_results(question, nil)
        }.to raise_error(ArgumentError, /Context cannot be nil/)
      end

      context "with different tones" do
        it "supports formal tone" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /语气：正式/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, tone: "formal")
        end

        it "supports casual tone" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /语气：随意/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, tone: "casual")
        end

        it "supports technical tone" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /语气：专业/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, tone: "technical")
        end
      end

      context "with custom max_length" do
        it "respects max_length parameter" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /答案长度不超过500个字符/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, max_length: 500)
        end
      end

      context "with citation options" do
        it "includes citations when requested" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /使用\[1\]、\[2\]等格式引用来源/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, include_citations: true)
        end

        it "excludes citations when disabled" do
          expect(mock_smart_prompt_engine).to receive(:call_worker).with(
            :generate_content,
            hash_including(content: /不需要引用来源/)
          ).and_return(llm_response)

          service.summarize_search_results(question, context, language: :zh_cn, include_citations: false)
        end
      end
    end

    context "in Simplified Chinese" do
      let(:question) { "什么是机器学习？" }
      let(:context) { "机器学习是人工智能的一个子集，它使计算机能够从数据中学习。" }
      let(:llm_response) do
        {
          "answer" => "机器学习是人工智能的一个分支，通过算法让计算机从数据中学习并做出预测或决策。",
          "confidence" => 0.89
        }.to_json
      end

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(llm_response)
      end

      it "generates summary in Chinese" do
        result = service.summarize_search_results(question, context, language: :zh_cn)

        expect(result[:answer]).to include("机器学习")
        expect(result[:confidence]).to be > 0
      end

      it "uses Chinese instructions in prompt" do
        expect(mock_smart_prompt_engine).to receive(:call_worker).with(
          :generate_content,
          hash_including(content: /基于以下搜索结果/)
        ).and_return(llm_response)

        service.summarize_search_results(question, context, language: :zh_cn)
      end
    end

    context "in Traditional Chinese" do
      let(:question) { "什麼是機器學習？" }
      let(:context) { "機器學習是人工智慧的一個子集，它使計算機能夠從數據中學習。" }
      let(:llm_response) do
        {
          "answer" => "機器學習是人工智慧的分支，通過演算法讓計算機從數據中學習。",
          "confidence" => 0.87
        }.to_json
      end

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(llm_response)
      end

      it "generates summary in Traditional Chinese" do
        result = service.summarize_search_results(question, context, language: :zh_tw)

        expect(result[:answer]).to include("機器學習")
      end

      it "uses Traditional Chinese instructions in prompt" do
        expect(mock_smart_prompt_engine).to receive(:call_worker).with(
          :generate_content,
          hash_including(content: /基於以下搜尋結果/)
        ).and_return(llm_response)

        service.summarize_search_results(question, context, language: :zh_tw)
      end
    end

    context "in Japanese" do
      let(:question) { "機械学習とは何ですか？" }
      let(:context) { "機械学習は人工知能の一部で、コンピュータがデータから学習できるようにします。" }
      let(:llm_response) do
        {
          "answer" => "機械学習は、データからパターンを学習し、予測や判断を行う人工知能の分野です。",
          "confidence" => 0.90
        }.to_json
      end

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(llm_response)
      end

      it "generates summary in Japanese" do
        result = service.summarize_search_results(question, context, language: :ja)

        expect(result[:answer]).to include("機械学習")
      end

      it "uses Japanese instructions in prompt" do
        expect(mock_smart_prompt_engine).to receive(:call_worker).with(
          :generate_content,
          hash_including(content: /検索結果に基づいて/)
        ).and_return(llm_response)

        service.summarize_search_results(question, context, language: :ja)
      end
    end

    context "with context truncation" do
      let(:long_context) { "x" * 5000 }

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(
          { "answer" => "Short answer", "confidence" => 0.8 }.to_json
        )
      end

      it "truncates long context" do
        result = service.summarize_search_results(question, long_context, language: :en)

        expect(mock_smart_prompt_engine).to have_received(:call_worker)
      end
    end

    context "when LLM response is not JSON" do
      let(:plain_response) { "Machine learning is a subset of AI." }

      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(plain_response)
      end

      it "handles plain text response" do
        result = service.summarize_search_results(question, context, language: :en)

        expect(result[:answer]).to eq(plain_response)
        expect(result[:confidence]).to eq(0.8)
      end
    end

    context "when LLM call fails" do
      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_raise(
          SmartRAG::Errors::LLMTimeoutError.new("Connection timeout")
        )
      end

      it "raises SummarizationServiceError" do
        expect {
          service.summarize_search_results(question, context)
        }.to raise_error(SmartRAG::Errors::SummarizationServiceError, /Summarization failed/)
      end

      it "retries on failure" do
        attempts = 0
        allow(mock_smart_prompt_engine).to receive(:call_worker) do
          attempts += 1
          attempts < 3 ? raise("Temporary error") : { "answer" => "Success", "confidence" => 0.9 }.to_json
        end

        result = service.summarize_search_results(question, context, language: :en, retries: 3)

        expect(result[:answer]).to eq("Success")
        expect(attempts).to eq(3)
      end
    end
  end

  describe "#summarize_text" do
    let(:text) { "Machine learning is a method of data analysis that automates analytical model building. It is a branch of artificial intelligence." }

    before do
      allow(mock_smart_prompt_engine).to receive(:call_worker).and_return(
        "Machine learning automates data analysis and is a branch of AI."
      )
    end

    it "generates a summary of text" do
      summary = service.summarize_text(text, language: :en)

      expect(summary).to be_a(String)
      expect(summary.length).to be < text.length
    end

    it "validates text is not nil" do
      expect {
        service.summarize_text(nil)
      }.to raise_error(ArgumentError, /Text cannot be nil/)
    end

    it "validates text is not empty" do
      expect {
        service.summarize_text("")
      }.to raise_error(ArgumentError, /Text cannot be nil/)
    end

    it "accepts custom max_length" do
      service.summarize_text(text, language: :en, max_length: 100)

      expect(mock_smart_prompt_engine).to have_received(:call_worker).with(
        :generate_content,
        hash_including(content: /100 characters/)
      )
    end

    it "auto-detects language" do
      service.summarize_text("机器学习是什么？", max_length: 100)

      expect(mock_smart_prompt_engine).to have_received(:call_worker).with(
        :generate_content,
        hash_including(content: /简洁中文/)
      )
    end

    context "when LLM call fails" do
      before do
        allow(mock_smart_prompt_engine).to receive(:call_worker).and_raise(
          SmartRAG::Errors::LLMConnectionError.new("API connection failed")
        )
      end

      it "raises SummarizationServiceError" do
        expect {
          service.summarize_text(text, language: :en)
        }.to raise_error(SmartRAG::Errors::SummarizationServiceError, /Text summarization failed/)
      end
    end
  end

  describe "#detect_language" do
    it "detects Chinese (Simplified)" do
      language = service.send(:detect_language, "机器学习是什么？")
      expect(language).to eq(:zh_cn)
    end

    it "detects Traditional Chinese as Chinese" do
      language = service.send(:detect_language, "機器學習是什麼？")
      expect(language).to eq(:zh_cn) # Our implementation groups all Chinese variants
    end

    it "detects Japanese" do
      language = service.send(:detect_language, "機械学習とは何ですか？")
      expect(language).to eq(:ja)
    end

    it "defaults to English for Latin text" do
      language = service.send(:detect_language, "What is machine learning?")
      expect(language).to eq(:en)
    end
  end

  describe "#truncate_context" do
    let(:long_context) { "x" * 5000 }

    it "truncates context longer than max_context_length" do
      truncated = service.send(:truncate_context, long_context)
      expect(truncated.length).to eq(4000 + "... (truncated)".length)
      expect(truncated).to include("(truncated)")
    end

    it "returns original context if within limit" do
      short_context = "x" * 1000
      truncated = service.send(:truncate_context, short_context)
      expect(truncated).to eq(short_context)
    end
  end

  describe "prompt building" do
    let(:question) { "What is machine learning?" }
    let(:context) { "Machine learning is a subset of AI." }
    let(:max_length) { 1000 }
    let(:tone) { "formal" }
    let(:include_citations) { true }

    describe "#build_chinese_summarization_prompt" do
      it "builds Chinese prompt correctly" do
        prompt = service.send(
          :build_chinese_summarization_prompt,
          question,
          context,
          max_length,
          tone,
          include_citations
        )

        expect(prompt).to include("基于以下搜索结果")
        expect(prompt).to include(question)
        expect(prompt).to include(context)
        expect(prompt).to include("答案长度不超过#{max_length}个字符")
        expect(prompt).to include("使用[1]、[2]等格式引用来源")
        expect(prompt).to include("以JSON格式输出")
      end
    end

    describe "#build_english_summarization_prompt" do
      it "builds English prompt correctly" do
        prompt = service.send(
          :build_english_summarization_prompt,
          question,
          context,
          max_length,
          tone,
          include_citations
        )

        expect(prompt).to include("Based on the following search results")
        expect(prompt).to include(question)
        expect(prompt).to include(context)
        expect(prompt).to include("Keep answer under #{max_length} characters")
        expect(prompt).to include("Cite sources using [1], [2] format")
        expect(prompt).to include("Output in JSON format")
      end
    end

    describe "#build_standalone_summary_prompt" do
      it "builds correct prompt for each language" do
        text = "Machine learning is a subset of AI."

        zh_prompt = service.send(:build_standalone_summary_prompt, text, :zh_cn, 500)
        expect(zh_prompt).to include("简洁中文")
        expect(zh_prompt).to include("500字以内")

        en_prompt = service.send(:build_standalone_summary_prompt, text, :en, 500)
        expect(en_prompt).to include("English")
        expect(en_prompt).to include("500 characters")

        ja_prompt = service.send(:build_standalone_summary_prompt, text, :ja, 500)
        expect(ja_prompt).to include("日本語")
        expect(ja_prompt).to include("500文字以内")
      end
    end
  end

  describe "response parsing" do
    describe "#parse_summary_response" do
      it "parses JSON response correctly" do
        json_response = '{"answer": "Machine learning is AI.", "confidence": 0.95}'
        result = service.send(:parse_summary_response, json_response)

        expect(result[:answer]).to eq("Machine learning is AI.")
        expect(result[:confidence]).to eq(0.95)
      end

      it "handles JSON with markdown code blocks" do
        markdown_response = "```json\n{\"answer\": \"ML is AI\", \"confidence\": 0.9}\n```"
        result = service.send(:parse_summary_response, markdown_response)

        expect(result[:answer]).to eq("ML is AI")
        expect(result[:confidence]).to eq(0.9)
      end

      it "defaults confidence to 0.8 for plain text" do
        plain_response = "Machine learning is a subset of AI."
        result = service.send(:parse_summary_response, plain_response)

        expect(result[:answer]).to eq(plain_response)
        expect(result[:confidence]).to eq(0.8)
      end
    end

    describe "#extract_text_from_response" do
      it "extracts text from JSON response" do
        json_response = '{"answer": "Machine learning is AI."}'
        result = service.send(:extract_text_from_response, json_response)

        expect(result).to eq("Machine learning is AI.")
      end

      it "removes markdown code blocks" do
        markdown_response = "```json\nMachine learning is AI.\n```"
        result = service.send(:extract_text_from_response, markdown_response)

        expect(result).to eq("Machine learning is AI.")
      end

      it "returns original text if not JSON" do
        plain_text = "Machine learning is AI."
        result = service.send(:extract_text_from_response, plain_text)

        expect(result).to eq(plain_text)
      end
    end
  end
end
