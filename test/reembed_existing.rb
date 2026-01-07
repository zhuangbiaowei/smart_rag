#!/usr/bin/env ruby

require "./lib/smart_rag"
require "logger"

# 为现有的 sections 重新生成 embeddings
class ExistingEmbeddingsGenerator
  def initialize
    @config = {
      database: {
        adapter: "postgresql",
        host: "localhost",
        database: "smart_rag_development",
        user: "rag_user",
        password: "rag_pwd",
      },
    }

    @rag = SmartRAG::SmartRAG.new(@config)
    @rag.logger = Logger.new(STDOUT)
    @rag.logger.level = Logger::INFO
  end

  def regenerate_embeddings_for_existing_sections
    puts "=" * 60
    puts "为现有的 sections 重新生成 embeddings..."
    puts "=" * 60

    # 获取所有没�?embeddings �?sections
    sections = SmartRAG::Models::SourceSection.without_embeddings(limit: 1000)
    total = sections.count

    if total == 0
      puts "所有 sections 都有 embeddings，无需重新生成。"
      return
    end

    puts "找到 #{total} 个没有 embeddings 的 sections"

    # 获取所有 sections（为了批量处理）
    all_sections = SmartRAG::Models::SourceSection.all
    all_total = all_sections.length

    # 创建 embedding service
    embedding_service = SmartRAG::Services::EmbeddingService.new
    embedding_manager = SmartRAG::Core::Embedding.new(@config.merge(logger: @rag.logger))

    success_count = 0
    failed_count = 0
    errors = []

    all_sections.each_with_index do |section, index|
      begin
        # 检查是否已经有 embedding
        existing = SmartRAG::Models::Embedding.by_section(section.id).first
        
        if existing
          puts "Section #{section.id} 已有 embedding，跳过"
          success_count += 1
        else
          # 生成 embedding
          embedding_service.generate_for_section(section)
          success_count += 1
        end

        # 每 20 个显示进度
        if (index + 1) % 20 == 0
          progress = ((index + 1).to_f / all_total * 100).round(1)
          @rag.logger.info "进度: #{index + 1}/#{all_total} (#{progress}%)"
        end
      rescue StandardError => e
        failed_count += 1
        errors << { section_id: section.id, error: e.message }
        @rag.logger.error "生成 embedding 失败 for section #{section.id}: #{e.message}"
      end
    end

    puts "\n" + "=" * 60
    puts "重新生成完成"
    puts "=" * 60
    puts "成功: #{success_count}"
    puts "失败: #{failed_count}"
    puts "总计: #{total}"

    if errors.any?
      puts "\n失败的 sections (前10个):"
      errors.first(10).each do |err|
        puts "  Section ID: #{err[:section_id]}, 错误: #{err[:error]}"
      end
    end

    # 验证
    verify_embeddings
  end

  def verify_embeddings
    puts "\n" + "=" * 60
    puts "验证 embeddings..."
    puts "=" * 60

    sections_count = SmartRAG::Models::SourceSection.count
    embeddings_count = SmartRAG::Models::Embedding.count

    puts "Sections: #{sections_count}"
    puts "Embeddings: #{embeddings_count}"

    # 检查哪�?sections 没有 embeddings
    sections_without = SmartRAG::Models::SourceSection.without_embeddings(limit: 100)
    if sections_without.any?
      puts "\n警告: #{sections_without.count} 个 sections 没有 embeddings"
    else
      puts "\n✓ 所有 sections 都有 embeddings"
    end

    # 测试向量搜索
    test_vector_search
  end

  def test_vector_search
    puts "\n" + "=" * 60
    puts "测试向量搜索..."
    puts "=" * 60

    embedding_manager = SmartRAG::Core::Embedding.new(@config.merge(logger: @rag.logger))

    test_queries = [
      "什么是导数？",
      "如何使用 Python 定义函数？",
      "生态系统中的能量是如何流动的？"
    ]

    test_queries.each_with_index do |query, index|
      puts "\n测试 #{index + 1}: #{query}"

      begin
        results = embedding_manager.search_similar(query, limit: 3, threshold: 0.4)

        if results.any?
          puts "  ✓ 找到 #{results.length} 个结果"
          results.first(2).each do |result|
            similarity = result[:similarity]
            section = result[:section]
            document = section.document

            puts "    - #{section.section_title} (#{document.title})"
            puts "      相似度: #{(similarity * 100).round(2)}%"
          end
        else
          puts "  ✗ 没有找到结果"
        end
      rescue StandardError => e
        puts "  ✗ 搜索失败: #{e.message}"
      end
    end
  end

  def run_all
    puts "SmartRAG Embeddings 重新生成工具"
    puts "=" * 60

    regenerate_embeddings_for_existing_sections

    puts "\n" + "=" * 60
    puts "重新生成流程完成！"
    puts "=" * 60
  end
end

# 命令行使用
if __FILE__ == $0
  generator = ExistingEmbeddingsGenerator.new

  case ARGV[0]
  when "regenerate", nil
    generator.run_all
  when "test"
    generator.test_vector_search
  else
    puts "使用方法:"
    puts "  ruby reembed_existing.rb [regenerate|test]"
    puts "\n选项:"
    puts "  regenerate - 重新生成 embeddings（默认）"
    puts "  test       - 仅测试向量搜索"
  end
end