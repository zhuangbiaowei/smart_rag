#!/usr/bin/env ruby

require "./lib/smart_rag"
require "logger"

# 导入测试文档到 RAG 数据库
class TestDocumentImporter
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
        api_key: "sk-qbmqiwoyvswtyzrdjrojkaplerhwcwoloulqlxgcjfjxpmpw",
      },
    }

    @smart_rag = SmartRAG::SmartRAG.new(@config)
    @smart_rag.logger = Logger.new(STDOUT)
    @smart_rag.logger.level = Logger::INFO

    @test_dir = File.expand_path(__dir__)
  end

  # 定义测试文档及其元数据
  def documents_info
    [
      {
        file: "python_basics.md",
        title: "Python 基础编程",
        tags: %w[编程 Python 基础 面向对象 数据结构],
        category: "技术",
      },
      {
        file: "javascript_guide.md",
        title: "JavaScript 开发指南",
        tags: %w[编程 JavaScript Web开发 异步编程 DOM],
        category: "技术",
      },
      {
        file: "machine_learning_intro.md",
        title: "机器学习入门",
        tags: %w[机器学习 AI 数据科学 算法 深度学习],
        category: "技术",
      },
      {
        file: "smart_chunking_demo.md",
        title: "智能分片演示",
        tags: %w[智能分片 合并 结构化段落],
        category: "技术",
      },
      {
        file: "data_modeling_primer.md",
        title: "数据建模实践",
        tags: %w[数据建模 知识图谱 实体关系 schema],
        category: "技术",
      },
      {
        file: "data_modeling_cheatsheet.md",
        title: "数据建模速查",
        tags: %w[数据建模 schema 约束 索引],
        category: "技术",
      },
      {
        file: "quantum_physics_intro.md",
        title: "量子物理导论",
        tags: %w[物理 量子力学 科学 波粒二象性 量子计算],
        category: "科学",
      },
      {
        file: "calculus_fundamentals.md",
        title: "微积分基础",
        tags: %w[数学 微积分 微分 积分 几何],
        category: "科学",
      },
      {
        file: "biology_ecosystem.md",
        title: "生物生态系统",
        tags: %w[生物 生态学 环境 生态系统 生物多样性],
        category: "科学",
      },
      {
        file: "astronomy_basics.md",
        title: "天文学基础",
        tags: %w[天文 宇宙 恒星 行星 黑洞],
        category: "科学",
      },
      {
        file: "ancient_civilizations.md",
        title: "古代文明",
        tags: %w[历史 古代文明 考古 文化 人类学],
        category: "历史",
      },
      {
        file: "world_war_ii.md",
        title: "第二次世界大战",
        tags: %w[历史 二战 军事 政治 地缘政治],
        category: "历史",
      },
      {
        file: "industrial_revolution.md",
        title: "工业革命",
        tags: %w[历史 工业革命 经济 技术 社会变革],
        category: "历史",
      },
      {
        file: "marketing_strategies.md",
        title: "营销策略",
        tags: %w[营销 商业 品牌 数字营销 客户关系],
        category: "商业",
      },
      {
        file: "financial_analysis.md",
        title: "财务分析",
        tags: %w[财务 分析 会计 投资 估值],
        category: "商业",
      },
      {
        file: "project_management.md",
        title: "项目管理",
        tags: %w[管理 项目管理 团队协作 敏捷 PMP],
        category: "商业",
      },
      {
        file: "startup_guide.md",
        title: "创业指南",
        tags: %w[创业 商业 投资 风险投资 产品开发],
        category: "商业",
      },
      {
        file: "python_basics_en.md",
        title: "Python Programming Basics",
        tags: %w[programming Python basics OOP data-structures],
        category: "技术",
        language: "en",
      },
      {
        file: "astronomy_basics_ja.md",
        title: "天文学の基礎",
        tags: %w[天文 宇宙 恒星 惑星 ブラックホール],
        category: "科学",
        language: "ja",
      },
      {
        file: "marketing_strategies_fr.md",
        title: "Strategie Marketing",
        tags: %w[marketing business marque numerique CRM],
        category: "商业",
        language: "fr",
      },
    ]
  end

  # 检查文档是否已存在
  def document_exists?(title)
    docs = @smart_rag.list_documents(search: title, per_page: 1)
    !docs[:documents].empty?
  end

  # 导入单个文档
  def import_document(doc_info, force: false)
    file_path = File.join(@test_dir, doc_info[:file])

    unless File.exist?(file_path)
      @smart_rag.logger.warn("文件不存在: #{file_path}")
      return { success: false, error: "File not found" }
    end

    # 检查文档是否已存在
    unless force || !document_exists?(doc_info[:title])
      return { success: true, skipped: true, title: doc_info[:title] }
    end

    begin
      result = @smart_rag.add_document(
        file_path,
        title: doc_info[:title],
        generate_embeddings: true,
        generate_tags: false, # 使用我们预定义的标签
        tags: doc_info[:tags],
        metadata: {
          category: doc_info[:category],
          source: "test_documents",
          language: doc_info[:language],
        },
      )

      {
        success: true,
        document_id: result[:document_id],
        title: doc_info[:title],
        section_count: result[:section_count],
      }
    rescue StandardError => e
      @smart_rag.logger.error("✗ 导入失败: #{doc_info[:title]} - #{e.message}")
      { success: false, error: e.message, title: doc_info[:title] }
    end
  end

  # 导入所有文档
  def import_all(force: false)
    results = {
      successful: [],
      failed: [],
      skipped: [],
      total_documents: documents_info.length,
    }

    documents_info.each_with_index do |doc_info, index|
      result = import_document(doc_info, force: force)

      if result[:success]
        if result[:skipped]
          results[:skipped] << result
        else
          results[:successful] << result
        end
      else
        results[:failed] << result
      end
    end

    print_summary(results)
    results
  end

  # 打印导入摘要
  def print_summary(results)
    @smart_rag.logger.info("\n" + "=" * 60)
    @smart_rag.logger.info("导入完成摘要")
    @smart_rag.logger.info("=" * 60)
    @smart_rag.logger.info("总文档数: #{results[:total_documents]}")
    @smart_rag.logger.info("成功导入: #{results[:successful].length}")
    @smart_rag.logger.info("已存在跳过: #{results[:skipped].length}")
    @smart_rag.logger.info("导入失败: #{results[:failed].length}")

    if results[:failed].any?
      @smart_rag.logger.info("\n失败的文档:")
      results[:failed].each do |failure|
        @smart_rag.logger.info("  - #{failure[:title]}: #{failure[:error]}")
      end
    end

    # 显示数据库统计
  end

  # 清理所有测试文档
  def clean_all
    docs = @smart_rag.list_documents(per_page: 100)
    docs[:documents].each do |doc|
      result = @smart_rag.remove_document(doc[:id])
    end
  end
end

# 命令行使用
if __FILE__ == $0
  importer = TestDocumentImporter.new

  case ARGV[0]
  when "import"
    force = ARGV[1] == "--force"
    importer.import_all(force: force)
  when "clean"
    importer.clean_all
  when "reimport"
    importer.clean_all
    puts "\n"
    importer.import_all(force: true)
  else
    puts "使用方法:"
    puts "  ruby import_doc.rb import [--force]  # 导入文档（--force 强制覆盖）"
    puts "  ruby import_doc.rb clean            # 清理所有文档"
    puts "  ruby import_doc.rb reimport          # 重新导入（清理后导入）"
  end
end
