#!/usr/bin/env ruby

require "./lib/smart_rag"
require "logger"
require "json"

# 测试 RAG 搜索功能
class RAGSearchTester
  def initialize
    @config = {
      database: {
        adapter: "postgresql",
        host: "localhost",
        database: "smart_rag_development",
        user: "rag_user",
        password: "rag_pwd",
      },
      llm: {
        provider: "openai",
        api_key: "sk-qbmqiwoyvswtyzrdjrojkaplerhwcwoloulqlxgcjfjxpmpw"
      },
    }

    @smart_rag = SmartRAG::SmartRAG.new(@config)
    @smart_rag.logger = Logger.new(STDOUT)
    @smart_rag.logger.level = Logger::INFO

    @test_results = []
  end

  # 打印分隔线
  def separator(title = nil)
    puts "\n" + "=" * 70
    puts title if title
    puts "=" * 70
  end

  # 打印搜索结果
  def print_search_results(results, show_content: false)
    puts "\n查询: #{results[:query]}"
    puts "结果数: #{results[:results].length}"
    puts "执行时间: #{results[:metadata][:execution_time_ms]}ms"
    puts "搜索类型: #{results[:metadata][:search_type] || "hybrid"}"

    puts "向量权重: #{results[:metadata][:alpha]}" if results[:metadata][:alpha]

    puts "\n搜索结果:"
    results[:results].each_with_index do |result, i|
      puts "\n#{i + 1}. #{result[:section_title]}"
      puts "   文档: #{result[:metadata][:document_title]}"
      puts "   相似度: #{(result[:similarity] * 100).round(2)}%" if result[:similarity]
      puts "   综合分数: #{(result[:combined_score] * 100).round(2)}%" if result[:combined_score]

      if show_content && result[:content]
        preview = result[:content][0..200].gsub("\n", " ")
        puts "   内容: #{preview}..."
      end
    end
  end

  # 记录测试结果
  def record_test(test_name, passed, details = {})
    @test_results << {
      name: test_name,
      passed: passed,
      details: details,
    }

    status = passed ? "✓ PASS" : "✗ FAIL"
    puts "\n#{status}: #{test_name}"
  end

  # 测试1: 向量搜索 - 语义相似性
  def test_vector_search
    separator("测试1: 向量搜索 - 语义相似性")

    test_cases = [
      {
        query: "什么是导数？",
        expected_document: "微积分基础",
        description: "数学概念查询",
      },
      {
        query: "如何使用 Python 定义函数？",
        expected_document: "Python 基础编程",
        description: "编程语法查询",
      },
      {
        query: "生态系统中的能量是如何流动的？",
        expected_document: "生物生态系统",
        description: "科学概念查询",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"
      puts "预期文档: #{test_case[:expected_document]}"

      results = @smart_rag.vector_search(
        test_case[:query],
        limit: 3,
        include_content: true,
      )

      if results[:results].any?
        top_result = results[:results].first
        actual_document = top_result[:document][:title]

        puts "实际文档: #{actual_document}"

        passed = actual_document.include?(test_case[:expected_document]) ||
                 test_case[:expected_document].include?(actual_document)

        record_test(
          "向量搜索 - #{test_case[:description]}",
          passed,
          query: test_case[:query],
          expected: test_case[:expected_document],
          actual: actual_document,
          score: top_result[:similarity],
        )
      else
        record_test(
          "向量搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          error: "No results",
        )
      end
    end
  end

  # 测试2: 全文搜索 - 精确关键词匹配
  def test_fulltext_search
    separator("测试2: 全文搜索 - 精确关键词匹配")

    test_cases = [
      {
        query: "机器学习",
        expected_document: "机器学习入门",
        description: "关键词精确匹配",
      },
      {
        query: "薛定谔猫",
        expected_document: "量子物理导论",
        description: "专业术语匹配",
      },
      {
        query: "第二次世界大战",
        expected_document: "第二次世界大战",
        description: "完整标题匹配",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"
      puts "预期文档: #{test_case[:expected_document]}"

      results = @smart_rag.fulltext_search(
        test_case[:query],
        limit: 3,
        include_content: true,
      )

      if results[:results].any?
        top_result = results[:results].first
        actual_document = top_result[:title].to_s

        puts "实际文档: #{actual_document}"

        passed = actual_document.include?(test_case[:expected_document]) ||
                 test_case[:expected_document].include?(actual_document)

        record_test(
          "全文搜索 - #{test_case[:description]}",
          passed,
          query: test_case[:query],
          expected: test_case[:expected_document],
          actual: actual_document,
        )
      else
        record_test(
          "全文搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          error: "No results",
        )
      end
    end
  end

  # 测试3: 混合搜索 - 结合向量和全文
  def test_hybrid_search
    separator("测试3: 混合搜索 - 结合向量和全文")

    test_cases = [
      {
        query: "Python",
        expected_title: "Python",
        description: "编程相关查询",
        alpha: 0.7,
      },
      {
        query: "工业革命",
        expected_title: "工业革命",
        description: "历史相关查询",
        alpha: 0.5,
      },
      {
        query: "两个或多个粒子可以形成关联状态，无论相距多远",
        expected_title: "量子物理导论",
        description: "科学概念查询",
        alpha: 0.8,
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"
      puts "预期标题包含: #{test_case[:expected_title]}"
      puts "向量权重: #{test_case[:alpha]}"

      begin
        results = @smart_rag.search(
          test_case[:query],
          search_type: "hybrid",
          limit: 3,
          alpha: test_case[:alpha],
          include_content: true,
        )

        if results[:results].any?
          top_result = results[:results].first
          doc_title = top_result[:metadata] && top_result[:metadata][:document_title]

          puts "文档标题: #{doc_title}"
          puts "综合分数: #{(top_result[:combined_score] * 100).round(2)}%"

          # Check if document title contains expected text
          passed = doc_title && (doc_title.include?(test_case[:expected_title]) ||
                                 (case test_case[:expected_title]
                                 when "技术"
                                   doc_title.include?("Python") || doc_title.include?("机器学习") || doc_title.include?("JavaScript")
                                 when "历史"
                                   doc_title.include?("历史") || doc_title.include?("文明") || doc_title.include?("革命")
                                 when "科学"
                                   doc_title.include?("科学") || doc_title.include?("生态") || doc_title.include?("物理") || doc_title.include?("数学")
                                 else
                                   false
                                 end))

          record_test(
            "混合搜索 - #{test_case[:description]}",
            passed,
            query: test_case[:query],
            expected_title: test_case[:expected_title],
            document_title: doc_title,
            score: top_result[:combined_score],
          )
        else
          record_test(
            "混合搜索 - #{test_case[:description]}",
            false,
            query: test_case[:query],
            error: "No results",
          )
        end
      rescue StandardError => e
        puts "搜索出错: #{e.message}"
        puts e.backtrace[0..5].join("\n")
        record_test(
          "混合搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          error: e.message,
        )
      end
    end
  end

  # 测试4: 跨领域搜索
  def test_cross_domain_search
    separator("测试4: 跨领域搜索")

    test_cases = [
      {
        query: "数学 计算机",
        expected_domains: %w[科学 技术],
        description: "数学与计算机科学的交叉",
      },
      {
        query: "工业革命 技术",
        expected_domains: %w[历史 技术],
        description: "历史与技术的交叉",
      },
      {
        query: "生物 数学",
        expected_domains: ["科学"],
        description: "生物学与数学的交叉",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"
      puts "预期领域: #{test_case[:expected_domains].join(", ")}"

      results = @smart_rag.search(
        test_case[:query],
        search_type: "hybrid",
        limit: 5,
        include_content: true,
      )

      if results[:results].any?
        actual_categories = results[:results]
          .map { |r| r[:metadata][:category] }
          .uniq

        puts "实际领域: #{actual_categories.join(", ")}"

        passed = test_case[:expected_domains].any? do |expected|
          actual_categories.include?(expected)
        end

        record_test(
          "跨领域搜索 - #{test_case[:description]}",
          passed,
          query: test_case[:query],
          expected_domains: test_case[:expected_domains],
          actual_categories: actual_categories,
        )
      else
        record_test(
          "跨领域搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          error: "No results",
        )
      end
    end
  end

  # 测试5: 基于标签的搜索
  def test_tag_based_search
    separator("测试5: 基于标签的搜索")

    # 首先获取所有标签
    tags_response = @smart_rag.list_tags(per_page: 100)
    all_tags = tags_response[:tags].map { |t| t[:name] }

    test_cases = [
      {
        tags: ["编程"],
        expected_documents: %w[Python JavaScript],
        description: "按编程标签筛选",
      },
      {
        tags: ["历史"],
        expected_documents: %w[文明 二战 工业革命],
        description: "按历史标签筛选",
      },
      {
        tags: %w[AI 机器学习],
        expected_documents: ["机器学习"],
        description: "多标签组合筛选",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "标签: #{test_case[:tags].join(", ")}"

      # 查找匹配的标签ID
      tag_ids = []
      test_case[:tags].each do |tag_name|
        matching_tags = all_tags.select { |t| t.include?(tag_name) || tag_name.include?(t) }
        if matching_tags.any?
          tag_obj = tags_response[:tags].find { |t| matching_tags.include?(t[:name]) }
          tag_ids << tag_obj[:id] if tag_obj
        end
      end

      if tag_ids.empty?
        puts "警告: 未找到匹配的标签"
        next
      end

      results = @smart_rag.search(
        "",
        search_type: "hybrid",
        limit: 10,
        filters: { tag_ids: tag_ids },
        include_content: true,
      )

      document_titles = results[:results]
        .map { |r| r[:metadata][:document_title] }
        .uniq

      puts "找到文档: #{document_titles.join(", ")}"

      passed = test_case[:expected_documents].any? do |expected|
        document_titles.any? { |actual| actual.include?(expected) }
      end

      record_test(
        "标签搜索 - #{test_case[:description]}",
        passed,
        tags: test_case[:tags],
        expected_documents: test_case[:expected_documents],
        actual_documents: document_titles,
      )
    end
  end

  # 测试6: 中文语义搜索
  def test_chinese_semantic_search
    separator("测试6: 中文语义搜索")

    test_cases = [
      {
        query: "Python",
        expected_category: "技术",
        description: "Python 编程",
      },
      {
        query: "生态系统",
        expected_category: "科学",
        description: "生态学问题",
      },
      {
        query: "古代文明",
        expected_category: "历史",
        description: "古代文明问题",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"

      results = @smart_rag.search(
        test_case[:query],
        search_type: "hybrid",
        limit: 3,
        language: "zh_cn",
        include_content: true,
      )

      if results[:results].any?
        top_result = results[:results].first
        actual_category = top_result[:metadata] && top_result[:metadata][:category]

        puts "找到类别: #{actual_category}"

        # Check if category matches expected or check document title as fallback
        passed = if actual_category
            actual_category == test_case[:expected_category]
          else
            # If metadata is missing or category is nil, check document title instead
            doc_title = top_result[:metadata] && top_result[:metadata][:document_title]
            puts "Category not found, checking document title: #{doc_title}"
            doc_title && ((doc_title.include?("Python") && test_case[:expected_category] == "技术") ||
                          (doc_title.include?("生物") && test_case[:expected_category] == "科学") ||
                          (doc_title.include?("文明") && test_case[:expected_category] == "历史") ||
                          (doc_title.include?("历史") && test_case[:expected_category] == "历史"))
          end

        record_test(
          "中文语义搜索 - #{test_case[:description]}",
          passed,
          query: test_case[:query],
          expected_category: test_case[:expected_category],
          actual_category: actual_category,
        )
      else
        record_test(
          "中文语义搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          error: "No results",
        )
      end
    end
  end

  # 测试7: 多语言全文搜索
  def test_multilingual_fulltext_search
    separator("测试7: 多语言全文搜索")

    test_cases = [
      {
        query: "Python Programming",
        expected_document: "Python Programming Basics",
        language: "en",
        description: "English fulltext search",
      },
      {
        query: "天文学",
        expected_document: "天文学の基礎",
        language: "ja",
        description: "Japanese fulltext search",
      },
      {
        query: "Strategie Marketing",
        expected_document: "Strategie Marketing",
        language: "fr",
        description: "French fulltext search",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"
      puts "语言: #{test_case[:language]}"
      puts "预期文档: #{test_case[:expected_document]}"

      results = @smart_rag.fulltext_search(
        test_case[:query],
        limit: 3,
        language: test_case[:language],
        include_content: true,
      )

      if results[:results].any?
        top_result = results[:results].first
        actual_document = top_result[:title].to_s

        puts "实际文档: #{actual_document}"

        passed = actual_document.include?(test_case[:expected_document]) ||
                 test_case[:expected_document].include?(actual_document)

        record_test(
          "多语言全文搜索 - #{test_case[:description]}",
          passed,
          query: test_case[:query],
          expected: test_case[:expected_document],
          actual: actual_document,
          language: test_case[:language],
        )
      else
        record_test(
          "多语言全文搜索 - #{test_case[:description]}",
          false,
          query: test_case[:query],
          language: test_case[:language],
          error: "No results",
        )
      end
    end
  end

  # 测试7: 不同 alpha 值的混合搜索
  def test_alpha_values
    separator("测试7: 不同 alpha 值的混合搜索")

    query = "Python 编程基础"
    alpha_values = [0.0, 0.3, 0.5, 0.7, 1.0]

    puts "\n查询: #{query}"

    alpha_results = {}
    alpha_scores = {}
    alpha_values.each do |alpha|
      results = @smart_rag.search(
        query,
        search_type: "hybrid",
        limit: 3,
        alpha: alpha,
        include_content: false,
      )

      top_doc = results[:results].first
      alpha_results[alpha] = top_doc ? top_doc[:metadata][:document_title] : nil
      alpha_scores[alpha] = top_doc ? top_doc[:combined_score] : nil

      score_info = top_doc ? " (score=#{top_doc[:combined_score].round(4)})" : ""
      puts "alpha=#{alpha}: #{top_doc ? top_doc[:metadata][:document_title] : "No results"}#{score_info}"
    end

    # 检查不同 alpha 是否产生不同的结果排序
    unique_results = alpha_results.values.compact.uniq
    score_values = alpha_scores.values.compact
    score_variation = score_values.uniq.length > 1
    passed = unique_results.length > 1 || score_variation

    record_test(
      "Alpha 值影响测试",
      passed,
      query: query,
      alpha_results: alpha_results,
      alpha_scores: alpha_scores,
      unique_results: unique_results.length,
      score_variation: score_variation,
    )
  end

  # 测试8: 布尔查询（全文搜索）
  def test_boolean_queries
    separator("测试8: 布尔查询（全文搜索）")

    test_cases = [
      {
        query: "Python AND 函数",
        description: "AND 操作符",
      },
      {
        query: "Python OR JavaScript",
        description: "OR 操作符",
      },
      {
        query: '"机器学习" AND "人工智能"',
        description: "短语搜索 + AND",
      },
    ]

    test_cases.each do |test_case|
      puts "\n测试: #{test_case[:description]}"
      puts "查询: #{test_case[:query]}"

      results = @smart_rag.fulltext_search(
        test_case[:query],
        limit: 5,
        include_content: true,
      )

      puts "结果数: #{results[:results].length}"

      passed = results[:results].any?

      record_test(
        "布尔查询 - #{test_case[:description]}",
        passed,
        query: test_case[:query],
        result_count: results[:results].length,
      )
    end
  end

  # 测试9: 搜索性能测试
  def test_smart_chunking_merge
    separator("测试9: 智能分片合并验证")

    query = '"碎片合并测试A" AND "碎片合并测试B"'

    puts "\n查询: #{query}"

    results = @smart_rag.fulltext_search(
      query,
      limit: 3,
      include_content: true,
      include_metadata: true,
    )

    top_result = results[:results].first
    actual_document = if top_result
                        top_result[:document_title] ||
                          (top_result[:metadata] && top_result[:metadata][:document_title]) ||
                          top_result[:title]
                      end

    puts "文档标题: #{actual_document || "No results"}"

    passed = actual_document && actual_document.include?("智能分片演示")

    record_test(
      "智能分片合并 - 跨标题短段落",
      passed,
      query: query,
      expected_document: "智能分片演示",
      actual_document: actual_document,
      result_count: results[:results].length,
    )
  end

  def test_rerank_tag_boost
    separator("测试10: 重排序标签加权")

    query = "知识图谱 数据建模"

    puts "\n查询: #{query}"

    results = @smart_rag.search(
      query,
      search_type: "hybrid",
      limit: 3,
      alpha: 0.7,
      include_content: false,
    )

    top_result = results[:results].first
    doc_title = top_result && top_result[:metadata] ? top_result[:metadata][:document_title] : nil

    puts "文档标题: #{doc_title || "No results"}"

    passed = doc_title && doc_title.include?("数据建模实践")

    record_test(
      "重排序 - 标签与关键词加权",
      passed,
      query: query,
      expected_document: "数据建模实践",
      document_title: doc_title,
      score: top_result ? top_result[:combined_score] : nil,
    )
  end

  def test_search_performance
    separator("测试11: 搜索性能测试")

    queries = [
      "Python 编程",
      "机器学习算法",
      "古代历史",
      "量子物理",
      "营销策略",
    ]

    search_types = %w[vector fulltext hybrid]

    performance_data = {}

    search_types.each do |search_type|
      puts "\n搜索类型: #{search_type}"
      execution_times = []

      queries.each do |query|
        results = @smart_rag.search(
          query,
          search_type: search_type,
          limit: 10,
        )

        execution_times << results[:metadata][:execution_time_ms]
        puts "  #{query}: #{results[:metadata][:execution_time_ms]}ms"
      end

      avg_time = execution_times.sum / execution_times.length
      max_time = execution_times.max
      min_time = execution_times.min

      performance_data[search_type] = {
        avg: avg_time,
        max: max_time,
        min: min_time,
      }

      puts "  平均: #{avg_time.round(2)}ms"
      puts "  最大: #{max_time}ms"
      puts "  最小: #{min_time}ms"
    end

    # 检查性能是否合理
    passed = performance_data.values.all? { |v| v[:avg] < 1000 }

    record_test(
      "搜索性能测试",
      passed,
      performance_data: performance_data,
    )
  end

  # 测试12: 结果多样性测试
  def test_result_diversity
    separator("测试12: 结果多样性测试")

    query = "科学"

    results = @smart_rag.search(
      query,
      search_type: "hybrid",
      limit: 10,
      include_content: false,
    )

    categories = results[:results]
      .map { |r| r[:metadata][:category] }
      .uniq

    puts "\n查询: #{query}"
    puts "结果数: #{results[:results].length}"
    puts "类别数: #{categories.length}"
    puts "类别: #{categories.join(", ")}"

    # 检查结果是否包含多个类别
    passed = categories.length >= 2

    record_test(
      "结果多样性测试",
      passed,
      query: query,
      result_count: results[:results].length,
      category_count: categories.length,
      categories: categories,
    )
  end

  # 打印测试总结
  def print_summary
    separator("测试总结")

    passed = @test_results.count { |r| r[:passed] }
    failed = @test_results.count { |r| !r[:passed] }
    total = @test_results.length

    puts "\n总测试数: #{total}"
    puts "通过: #{passed}"
    puts "失败: #{failed}"
    puts "通过率: #{(passed.to_f / total * 100).round(2)}%"

    return unless failed > 0

    puts "\n失败的测试:"
    @test_results.select { |r| !r[:passed] }.each do |result|
      puts "  ✗ #{result[:name]}"
      puts "    详情: #{result[:details].inspect}"
    end
  end

  # 运行所有测试
  def run_all_tests
    separator("SmartRAG 搜索功能测试")

    # 检查数据库状态
    stats = @smart_rag.statistics
    puts "数据库状态:"
    puts "  文档数: #{stats[:document_count]}"
    puts "  章节数: #{stats[:section_count]}"
    puts "  嵌入数: #{stats[:embedding_count]}"
    puts "  标签数: #{stats[:tag_count]}"

    if stats[:document_count] == 0
      puts "\n警告: 数据库中没有文档，请先运行 import_doc.rb 导入测试文档"
      return
    end

    # 运行测试
    begin
      test_vector_search
      test_fulltext_search
      test_hybrid_search
      test_cross_domain_search
      test_tag_based_search
      test_chinese_semantic_search
      test_multilingual_fulltext_search
      test_alpha_values
      test_boolean_queries
      test_smart_chunking_merge
      test_rerank_tag_boost
      test_search_performance
      test_result_diversity
    rescue StandardError => e
      puts "\n测试执行出错: #{e.message}"
      puts e.backtrace
    end

    # 打印总结
    print_summary
  end

  # 运行特定测试
  def run_test(test_name)
    test_method = "test_#{test_name}"

    if respond_to?(test_method)
      send(test_method)
    else
      puts "未找到测试: #{test_name}"
      puts "可用测试: vector_search, fulltext_search, hybrid_search, cross_domain_search,
             tag_based_search, chinese_semantic_search, multilingual_fulltext_search, alpha_values, boolean_queries,
             smart_chunking_merge, rerank_tag_boost, search_performance, result_diversity"
    end
  end
end

# 命令行使用
if __FILE__ == $0
  tester = RAGSearchTester.new

  case ARGV[0]
  when "all", nil
    tester.run_all_tests
  when "vector"
    tester.run_test("vector_search")
  when "fulltext"
    tester.run_test("fulltext_search")
  when "hybrid"
    tester.run_test("hybrid_search")
  when "cross"
    tester.run_test("cross_domain_search")
  when "tags"
    tester.run_test("tag_based_search")
  when "chinese"
    tester.run_test("chinese_semantic_search")
  when "multilingual"
    tester.run_test("multilingual_fulltext_search")
  when "alpha"
    tester.run_test("alpha_values")
  when "boolean"
    tester.run_test("boolean_queries")
  when "performance"
    tester.run_test("search_performance")
  when "chunking"
    tester.run_test("smart_chunking_merge")
  when "rerank"
    tester.run_test("rerank_tag_boost")
  when "diversity"
    tester.run_test("result_diversity")
  else
    puts "使用方法:"
    puts "  ruby test_rag.rb [all|vector|fulltext|hybrid|cross|tags|chinese|alpha|boolean|performance|chunking|rerank|diversity]"
    puts "\n测试选项:"
    puts "  all        - 运行所有测试（默认）"
    puts "  vector     - 向量搜索测试"
    puts "  fulltext   - 全文搜索测试"
    puts "  hybrid     - 混合搜索测试"
    puts "  cross      - 跨领域搜索测试"
    puts "  tags       - 基于标签的搜索测试"
    puts "  chinese    - 中文语义搜索测试"
    puts "  multilingual - 多语言全文搜索测试"
    puts "  alpha      - 不同 alpha 值测试"
    puts "  boolean    - 布尔查询测试"
    puts "  performance - 性能测试"
    puts "  chunking   - 智能分片合并测试"
    puts "  rerank     - 重排序标签加权测试"
    puts "  diversity  - 结果多样性测试"
  end
end
