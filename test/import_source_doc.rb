#!/usr/bin/env ruby

require "./lib/smart_rag"
require "json"
require "logger"
require "fileutils"
require "open-uri"

class SourceDocumentImporter
  def initialize(json_path:, logger: Logger.new(STDOUT))
    @json_path = json_path
    @logger = logger
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
    @smart_rag.logger = @logger
    @smart_rag.logger.level = Logger::INFO

    @output_dir = File.join(File.expand_path(__dir__), "imported_sources")
    FileUtils.mkdir_p(@output_dir)
  end

  def import_all
    rows = load_rows
    summary = {
      total: rows.length,
      inserted: 0,
      skipped: 0,
      failed: 0
    }

    rows.each_with_index do |row, index|
      attrs = normalize_row(row)
      if attrs[:title].to_s.strip.empty?
        summary[:skipped] += 1
        next
      end
      if document_exists_by_title?(attrs[:title])
        @logger.info("Skipping existing document by title: #{attrs[:title]}")
        summary[:skipped] += 1
        next
      end

      file_path = fetch_and_convert(attrs, index)
      if file_path.nil?
        cleanup_source_files(index)
        summary[:failed] += 1
        next
      end

      result = @smart_rag.add_document(
        file_path,
        url: attrs[:url],
        title: attrs[:title],
        generate_embeddings: true,
        generate_tags: false,
        tags: [],
        metadata: {
          source: "source_documents_export",
          url: attrs[:url],
          description: attrs[:description],
        },
      )

      summary[:inserted] += 1 if result
    rescue StandardError => e
      summary[:failed] += 1
      @logger.warn("Row #{index + 1} failed: #{e.message}")
    end

    summary
  end

  private

  def load_rows
    unless File.exist?(@json_path)
      raise ArgumentError, "JSON file not found: #{@json_path}"
    end

    parsed = JSON.parse(File.read(@json_path))
    return parsed if parsed.is_a?(Array)

    raise ArgumentError, "JSON file must contain an array of objects"
  end

  def normalize_row(row)
    title = row["title"] || row[:title]
    description = row["description"] || row[:description]
    url = row["url"] || row[:url]

    {
      title: title,
      description: description,
      url: url
    }
  end

  def fetch_and_convert(attrs, index)
    url = attrs[:url].to_s.strip
    if url.empty?
      return write_fallback_markdown(attrs, index)
    end

    downloaded_path = download_source(url, index)
    return nil unless downloaded_path

    converted_path = convert_with_markitdown(downloaded_path, index)
    return nil unless converted_path

    converted_path
  end

  def cleanup_source_files(index)
    base = "source_#{index + 1}"
    Dir.glob(File.join(@output_dir, "#{base}.*")).each do |path|
      File.delete(path) if File.exist?(path)
    end
  rescue StandardError => e
    @logger.warn("Failed to cleanup files for #{base}: #{e.message}")
  end

  def document_exists_by_title?(title)
    return false if title.to_s.strip.empty?

    ::SmartRAG::Models::SourceDocument.where(title: title).first != nil
  end

  def download_source(url, index)
    uri = URI.parse(url)
    ext = File.extname(uri.path)
    ext = ".bin" if ext.empty?
    filename = "source_#{index + 1}#{ext}"
    path = File.join(@output_dir, filename)

    URI.open(url) do |io|
      File.binwrite(path, io.read)
    end

    path
  rescue StandardError => e
    @logger.warn("Download failed for #{url}: #{e.message}")
    nil
  end

  def convert_with_markitdown(input_path, index)
    output_path = File.join(@output_dir, "source_#{index + 1}.md")
    command = %(python3 -m markitdown "#{input_path}" -o "#{output_path}")
    success = system(command)
    return output_path if success && File.exist?(output_path)

    @logger.warn("markitdown conversion failed for #{input_path}")
    nil
  end

  def write_fallback_markdown(attrs, index)
    safe_title = attrs[:title].to_s.strip.gsub(/[^\w\u4e00-\u9fff\- ]+/, "").gsub(/\s+/, "_")
    safe_title = "doc_#{index + 1}" if safe_title.empty?
    filename = "#{safe_title}_#{index + 1}.md"
    path = File.join(@output_dir, filename)

    content_lines = []
    content_lines << "# #{attrs[:title]}"
    content_lines << ""
    content_lines << attrs[:description].to_s.strip unless attrs[:description].to_s.strip.empty?
    if attrs[:url].to_s.strip != ""
      content_lines << ""
      content_lines << "来源: #{attrs[:url]}"
    end

    File.write(path, content_lines.join("\n").strip + "\n")
    path
  end
end

if __FILE__ == $0
  json_path = ARGV[0] || File.join(Dir.pwd, "source_documents_export.json")

  importer = SourceDocumentImporter.new(json_path: json_path)
  summary = importer.import_all

  puts "Import finished."
  puts "Total: #{summary[:total]}"
  puts "Inserted: #{summary[:inserted]}"
  puts "Skipped: #{summary[:skipped]}"
  puts "Failed: #{summary[:failed]}"
end
