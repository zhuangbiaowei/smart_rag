#!/usr/bin/env ruby

require "./lib/smart_rag"
require "logger"

# 重新生成所有 embeddings 以确保向量一致性
class EmbeddingRegenerator
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

  # 删除所有现有的 embeddings
  def clear_embeddings
    puts "=" * 60
    puts "删除所有现有的 embeddings..."
    puts "=" * 60

    count = SmartRAG::Models::Embedding.delete
    puts "已删除 #{count} 个 embeddings"

    count
  rescue StandardError => e
    @rag.logger.error "删除 embeddings 失败: #{e.message}"
    raise
  end

  # 重新生成 embeddings
  def regenerate_embeddings
    puts "\n" + "=" * 60
    puts "重新生成所有 embeddings..."
    puts "=" * 60

    # 获取所有 sections
    sections = SmartRAG::Models::SourceSection.all
    total = sections.length
    puts "找到 #{total} 个 sections"

    # 创建 embedding service
    embedding_service = SmartRAG::Services::EmbeddingService.new
    embedding_manager = SmartRAG::Core::Embedding.new(@config.merge(logger: @rag.logger))

    success_count = 0
    failed_count = 0
    errors = []

    sections.each_with_index do |section, index|
      begin
        # 生成 embedding
        embedding_service.generate_for_section(section)

        success_count += 1

        # 每 50 个显示进度
        if (index + 1) % 50 == 0 || index == total - 1
          progress = ((index + 1).to_f / total * 100).round(1)
          @rag.logger.info "进度: #{index + 1}/#{total} (#{progress}%)"
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
  end

  # 验证 embeddings
  def verify_embeddings
    puts "\n" + "=" * 60
    puts "验证 embeddings..."
    puts "=" * 60

    sections_count = SmartRAG::Models::SourceSection.count
    embeddings_count = SmartRAG::Models::Embedding.count

    puts "Sections: #{sections_count}"
    puts "Embeddings: #{embeddings_count}"

    # 检查哪些 sections 没有 embeddings
    sections_without = SmartRAG::Models::SourceSection.without_embeddings(limit: 100)
    if sections_without.any?
      puts "\n警告: #{sections_without.count} 个 sections 没有 embeddings"
      puts "Sections without embeddings (前10个):"
      sections_without.first(10).each do |section|
        puts "  ID: #{section.id}, Title: #{section.section_title}"
      end
    else
      puts "\n✓ 所有 sections 都有 embeddings"
    end

    # 检查 embeddings 的向量
    sample_embeddings = SmartRAG::Models::Embedding.limit(5)
    puts "\n示例 embeddings (前5个):"
    sample_embeddings.each do |emb|
      section = emb.section
      puts "  Embedding ID: #{emb.id}, Section: #{section.section_title}, Vector 采样: #{emb.vector.to_s[0..50]}..."
    end
  end

  # 测试向量搜索
  def test_vector_search
    puts "\n" + "=" * 60
    puts "测试向量搜索..."
    puts "=" * 60

    test_queries = [
      "什么是导数？",
      "如何使用 Python 定义函数？",
      "生态系统中的能量是如何流动的？"
    ]

    embedding_manager = SmartRAG::Core::Embedding.new(@config.merge(logger: @rag.logger))

    test_queries.each_with_index do |query, index|
      puts "\n测试 #{index + 1}: #{query}"
      
      begin
        results = embedding_manager.search_similar(query, limit: 3, threshold: 0.4)
        
        if results.any?
          puts "  ✓ 找到 #{results.length} 个结果"
          results.each_with_index do |result, i|
            similarity = result[:similarity]
            section = result[:section]
            document = section.document
            
            puts "    #{i+1}. #{section.section_title} (#{document.title})"
            puts "       相似度: #{(similarity * 100).round(2)}%"
          end
        else
          puts "  ✗ 没有找到结果"
        end
      rescue StandardError => e
        puts "  ✗ 搜索失败: #{e.message}"
      end
    end
  end

  # 运行完整流程
  def run_all
    puts "SmartRAG Embedding 重新生成工具"
    puts "=" * 60
    
    # 1. 删除现有 embeddings
    clear_embeddings
    
    # 2. 重新生成 embeddings
    regenerate_embeddings
    
    # 3. 验证 embeddings
    verify_embeddings
    
    # 4. 测试向量搜索
    test_vector_search
    
    puts "\n" + "=" * 60
    puts "重新生成流程完成！"
    puts "=" * 60
  end
end

# 命令行使用
if __FILE__ == $0
  regenerator = EmbeddingRegenerator.new
  
  case ARGV[0]
  when "clear"
    regenerator.clear_embeddings
  when "regenerate"
    regenerator.regenerate_embeddings
  when "verify"
    regenerator.verify_embeddings
  when "test"
    regenerator.test_vector_search
  when "all", nil
    regenerator.run_all
  else
    puts "使用方法:"
    puts "  ruby reembed_all.rb [all|clear|regenerate|verify|test]"
    puts "\n选项:"
    puts "  all        - 运行完整流程（删除 + 重新生成 + 验证 + 测试）"
    puts "  clear      - 仅删除现有 embeddings"
    puts "  regenerate - 仅重新生成 embeddings"
    puts "  verify     - 仅验证 embeddings"
    puts "  test       - 仅测试向量搜索"
  end
end
