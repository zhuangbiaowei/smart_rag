require 'uri'
require 'net/http'
require 'fileutils'
require 'tempfile'
require_relative '../../smart_rag'
require_relative '../models'
require_relative '../chunker/markdown_chunker'
require_relative '../smart_chunking/pipeline'

module SmartRAG
  module Core
    # DocumentProcessor handles document downloading, conversion, chunking, and storage
    class DocumentProcessor
      attr_reader :config, :embedding_manager, :tag_service

      def initialize(config = {})
        @config = config
        @embedding_manager = config[:embedding_manager]
        @tag_service = config[:tag_service]
        @logger = config[:logger] || Logger.new(STDOUT)
        @download_dir = config[:download_dir] || Dir.tmpdir
        @default_chunk_size = config[:chunk_size] || 2000
        @default_overlap = config[:overlap] || 200

        # Update config with defaults
        @config[:logger] = @logger
        @config[:download_dir] = @download_dir
        @config[:chunk_size] = @default_chunk_size
        @config[:overlap] = @default_overlap
      end

      # Process a document from URL or local file
      # @param [String] source URL or file path
      # @param [Hash] options Processing options
      # @return [::SmartRAG::Models::SourceDocument] processed document
      def process(source, options = {})
        @logger.info "Processing document from: #{source}"

        # Step 1: Download if it's a URL
        file_path = if source =~ %r{\Ahttps?://}
                      download_from_url(source, options)
                    elsif File.exist?(source)
                      source
                    else
                      raise ArgumentError, "Invalid source: #{source}. Must be a valid URL or file path."
                    end

        # Step 2: Extract metadata
        metadata = extract_metadata(file_path, options)

        # Step 3: Convert to markdown
        markdown_content = convert_to_markdown(file_path, options)

        # Add markdown content to metadata for language detection
        metadata[:content] = markdown_content if metadata[:content].nil? || metadata[:content].empty?

        # Step 4: Create or update document record
        document = create_or_update_document(source, metadata, options)

        # Step 5: Chunk content
        chunks = chunk_content(markdown_content, options)

        # Step 6: Save sections
        save_sections(document, chunks, options)

        # Step 7: Update document status
        document.set_download_state(:completed)

        @logger.info "Successfully processed document: #{document.title}"
        document
      rescue StandardError => e
        @logger.error "Failed to process document #{source}: #{e.message}"
        @logger.error e.backtrace.join("\n")

        # Mark as failed if document was created
        @document.set_download_state(:failed) if defined?(@document) && @document

        raise e
      ensure
        # Clean up temporary downloaded files
        if defined?(@downloaded_file) && @downloaded_file && File.exist?(@downloaded_file)
          File.delete(@downloaded_file)
          @logger.debug "Cleaned up temporary file: #{@downloaded_file}"
        end
      end

      # Create a document and return document with sections
      # @param [String] source URL or file path
      # @param [Hash] options Processing options
      # @return [Hash] Document and sections { document: SourceDocument, sections: [] }
      def create_document(source, options = {})
        @logger.info "Creating document from: #{source}"

        # Step 1: Download if it's a URL
        file_path = if source =~ %r{\Ahttps?://}
                      download_from_url(source, options)
                    elsif File.exist?(source)
                      source
                    else
                      raise ArgumentError, "Invalid source: #{source}. Must be a valid URL or file path."
                    end

        # Step 2: Extract metadata
        metadata = extract_metadata(file_path, options)

        # Step 3: Convert to markdown
        markdown_content = convert_to_markdown(file_path, options)

        # Add markdown content to metadata for language detection
        metadata[:content] = markdown_content if metadata[:content].nil? || metadata[:content].empty?

        # Step 4: Create or update document record
        document = create_or_update_document(source, metadata, options)

        # Step 5: Chunk content
        chunks = chunk_content(markdown_content, options)

        # Step 6: Save sections (and optionally generate embeddings/tags)
        sections = save_sections(document, chunks, options)

        # Step 7: Update document status
        document.set_download_state(:completed)

        @logger.info "Successfully created document: #{document.title} with #{sections.length} sections"

        # Return hash with document and sections as expected by the API
        {
          document: document,
          sections: sections
        }
      rescue StandardError => e
        @logger.error "Failed to create document #{source}: #{e.message}"
        @logger.error e.backtrace.join("\n")

        # Mark as failed if document was created
        @document.set_download_state(:failed) if defined?(@document) && @document

        raise e
      ensure
        # Clean up temporary downloaded files
        if defined?(@downloaded_file) && @downloaded_file && File.exist?(@downloaded_file)
          File.delete(@downloaded_file)
          @logger.debug "Cleaned up temporary file: #{@downloaded_file}"
        end
      end

      # Download document from URL
      # @param [String] url Source URL
      # @param [Hash] options Download options
      # @return [String] Path to downloaded file
      def download_from_url(url, options = {})
        uri = URI.parse(url)
        @logger.info "Downloading from URL: #{url}"

        # Create temp file with appropriate extension
        ext = File.extname(uri.path)
        ext = '.html' if ext.empty?
        temp_file = Tempfile.new(['doc_', ext], @download_dir)
        temp_path = temp_file.path
        temp_file.close

        # Download the file
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new(uri)
          # Set user agent to avoid being blocked
          request['User-Agent'] = 'SmartRAG Document Processor/1.0'

          response = http.request(request)

          case response.code
          when '200'
            File.write(temp_path, response.body)
          when '301', '302', '303', '307', '308'
            # Follow redirect
            redirect_url = response['Location']
            @logger.info "Redirecting to: #{redirect_url}"
            return download_from_url(redirect_url, options)
          else
            raise "HTTP Error: #{response.code} - #{response.message}"
          end
        end

        @downloaded_file = temp_path
        @logger.info "Downloaded file to: #{temp_path}"
        temp_path
      rescue StandardError => e
        @logger.error "Download failed: #{e.message}"
        raise e
      end

      # Extract metadata from file
      # @param [String] file_path Path to file
      # @param [Hash] options Metadata options
      # @return [Hash] Extracted metadata
      def extract_metadata(file_path, options = {})
        metadata = {
          file_path: file_path,
          file_size: File.size(file_path),
          file_type: File.extname(file_path).downcase,
          created_at: File.ctime(file_path),
          modified_at: File.mtime(file_path)
        }

        # Try to extract more metadata based on file type
        case metadata[:file_type]
        when '.pdf'
          metadata.merge!(extract_pdf_metadata(file_path))
        when '.docx', '.doc'
          metadata.merge!(extract_docx_metadata(file_path))
        when '.html', '.htm'
          metadata.merge!(extract_html_metadata(file_path))
        end

        # Use provided title if available (for backward compatibility)
        metadata[:title] = options[:title] if options[:title]

        # Override with provided metadata
        metadata.merge!(options[:metadata] || {})

        @logger.debug "Extracted metadata: #{metadata.except(:file_path)}"
        metadata
      rescue StandardError => e
        @logger.warn "Failed to extract metadata: #{e.message}"
        metadata
      end

      # Convert document to markdown using markitdown
      # @param [String] file_path Path to source file
      # @param [Hash] options Conversion options
      # @return [String] Converted markdown content
      def convert_to_markdown(file_path, options = {})
        @logger.info "Converting #{file_path} to markdown"

        ext = File.extname(file_path).downcase
        if ['.md', '.markdown'].include?(ext)
          @logger.info "Detected markdown source; skipping conversion"
          return File.read(file_path)
        end

        # Use markitdown bridge for conversion
        require_relative 'markitdown_bridge'



        max_retries = options[:max_retries] || 3
        retry_delay = options[:retry_delay] || 1

        bridge = MarkitdownBridge.new
        unless bridge.available?
          raise LoadError, 'markitdown Python package is not installed. Install with: pip install markitdown'
        end

        # Check if file exists before attempting conversion
        raise "File not found: #{file_path}" unless File.exist?(file_path)

        retries = 0
        begin
          markdown = bridge.convert(file_path)

          raise 'Conversion failed: empty result' if markdown.nil? || markdown.strip.empty?

          @logger.info "Successfully converted to markdown (#{markdown.length} chars)"
          markdown
        rescue StandardError => e
          retries += 1
          if retries < max_retries
            @logger.warn "Conversion attempt #{retries} failed: #{e.message}. Retrying in #{retry_delay}s..."
            sleep retry_delay
            retry
          end

          @logger.error "All conversion attempts failed: #{e.message}"
          raise "Conversion failed after #{max_retries} attempts: #{e.message}"
        end
      rescue LoadError => e
        @logger.error e.message
        raise e
      rescue StandardError => e
        @logger.error "Conversion failed: #{e.message}"
        raise e
      end

      # Create or update document record
      # @param [String] source Original source
      # @param [Hash] metadata Document metadata
      # @param [Hash] options Document options
      # @return [::SmartRAG::Models::SourceDocument]
      def create_or_update_document(source, metadata, options = {})
        original_url = options[:url] || metadata[:url] || source
        doc_attributes = {
          url: original_url,
          title: metadata[:title] || File.basename(source),
          author: metadata[:author],
          description: metadata[:description],
          publication_date: metadata[:publication_date],
          language: metadata[:language] || detect_language(metadata[:content] || ''),
          download_state: ::SmartRAG::Models::SourceDocument::DOWNLOAD_STATES[:pending],
          metadata: metadata.to_json
        }

        @document = ::SmartRAG::Models::SourceDocument.create_or_update(doc_attributes)

        if @document.id.nil? || !@document.exists?
          @logger.error "Document save failed: #{@document.errors.inspect}"
          raise "Failed to save document: #{@document.errors.inspect}"
        end

        @logger.info "Created document record: #{@document.id}"
        @document
      rescue StandardError => e
        @logger.error "Exception creating document: #{e.message}"
        raise e
      end

      # Chunk markdown content into sections
      # @param [String] markdown_content Content to chunk
      # @param [Hash] options Chunking options
      # @return [Array<Hash>] Array of chunk hashes
      def chunk_content(markdown_content, options = {})
        use_smart = options.fetch(:smart_chunking, true)

        if use_smart
          token_limit = options[:chunk_token_num] || 400
          doc_type = options[:doc_type] || :general
          pipeline = ::SmartRAG::SmartChunking::Pipeline.new(token_limit: token_limit)
          chunks = pipeline.chunk(markdown_content, doc_type: doc_type, options: options)
        else
          chunker = options[:chunker] || ::SmartRAG::Chunker::MarkdownChunker.new(
            chunk_size: options[:chunk_size] || @default_chunk_size,
            overlap: options[:overlap] || @default_overlap
          )
          chunks = chunker.chunk(markdown_content)
        end
        @logger.info "Created #{chunks.length} chunks"
        chunks
      end

      # Save chunk sections to database
      # @param [::SmartRAG::Models::SourceDocument] document Document record
      # @param [Array<Hash>] chunks Array of chunk hashes
      # @param [Hash] options Save options
      # @option options [Boolean] :generate_embeddings Whether to generate embeddings for sections
      # @option options [Boolean] :generate_tags Whether to generate tags for sections
      def save_sections(document, chunks, options = {})
        sections = chunks.each_with_index.map do |chunk, index|
          {
            document_id: document.id,
            section_title: chunk[:title],
            section_number: index + 1,
            content: chunk[:content],
            created_at: Time.now,
            updated_at: Time.now
          }
        end

        ::SmartRAG::Models::SourceSection.batch_insert(sections)
        @logger.info "Saved #{sections.length} sections to database"

        # Get the created sections with their IDs
        created_sections = ::SmartRAG::Models::SourceSection.where(document_id: document.id).all

        # Generate embeddings if requested
        generate_embeddings_for_sections(created_sections) if options[:generate_embeddings] && @embedding_manager

        # Generate tags if requested
        generate_tags_for_sections(created_sections) if options[:generate_tags] && @tag_service

        created_sections
      end

      # Generate embeddings for sections
      def generate_embeddings_for_sections(sections)
        @logger.info "Generating embeddings for #{sections.length} sections..."

        sections.each_with_index do |section, index|
          vector = @embedding_manager.generate_embedding(section.content)
          if vector && vector.is_a?(Array) && !vector.empty?
            ::SmartRAG::Models::Embedding.create(
              source_id: section.id,
              vector: "[#{vector.join(',')}]"
            )
            @logger.debug "Generated embedding for section #{index + 1}/#{sections.length}"
          end
        rescue StandardError => e
          @logger.warn "Failed to generate embedding for section #{section.id}: #{e.message}"
        end

        @logger.info 'Embeddings generation completed'
      end

      # Generate tags for sections
      def generate_tags_for_sections(sections)
        @logger.info "Generating tags for #{sections.length} sections..."

        sections.each_with_index do |section, index|
          tags = @tag_service.generate_tags(section.content, section.section_title,
                                            [detect_language(section.content)])

          if tags && tags[:content_tags] && !tags[:content_tags].empty?
            # Create or find tags and associate with section
            tags[:content_tags].each do |tag_name|
              tag = ::SmartRAG::Models::Tag.find_or_create(name: tag_name)

              # Check if association already exists
              existing = ::SmartRAG::Models::SectionTag.find(
                section_id: section.id,
                tag_id: tag.id
              )

              # Create association if it doesn't exist
              next unless existing.nil?

              ::SmartRAG::Models::SectionTag.create(
                section_id: section.id,
                tag_id: tag.id
              )
            end
            @logger.debug "Generated #{tags[:content_tags].length} tags for section #{index + 1}/#{sections.length}"
          end
        rescue StandardError => e
          @logger.warn "Failed to generate tags for section #{section.id}: #{e.message}"
        end

        @logger.info 'Tags generation completed'
      end

      # Detect language from text
      # @param [String] text Text to analyze
      # @return [String] Language code (ISO 639-1)
      def detect_language(text)
        return 'en' if text.nil? || text.empty?

        # Heuristic: decide by CJK character ratios to avoid short mixed-language bias.
        ja_count = text.scan(/[\u3040-\u309f\u30a0-\u30ff]/).length
        ko_count = text.scan(/[\uac00-\ud7af]/).length
        zh_count = text.scan(/[\u4e00-\u9fff]/).length
        cjk_total = ja_count + ko_count + zh_count

        return 'en' if cjk_total.zero?

        ja_ratio = ja_count.to_f / cjk_total
        ko_ratio = ko_count.to_f / cjk_total
        zh_ratio = zh_count.to_f / cjk_total

        return 'ja' if ja_ratio >= 0.3 && ja_ratio > zh_ratio && ja_ratio > ko_ratio
        return 'ko' if ko_ratio >= 0.3 && ko_ratio > zh_ratio

        'zh'
      rescue StandardError => e
        @logger.warn "Language detection failed: #{e.message}, defaulting to 'en'"
        'en'
      end

      # Extract metadata from PDF files
      # @param [String] file_path Path to PDF
      # @return [Hash] PDF metadata
      def extract_pdf_metadata(_file_path)
        # This would require a PDF parsing library
        # For now, return empty hash
        {}
      end

      # Extract metadata from DOCX files
      # @param [String] file_path Path to DOCX
      # @return [Hash] DOCX metadata
      def extract_docx_metadata(_file_path)
        # This would require a DOCX parsing library
        # For now, return empty hash
        {}
      end

      # Extract metadata from HTML files
      # @param [String] file_path Path to HTML
      # @return [Hash] HTML metadata
      def extract_html_metadata(file_path)
        content = File.read(file_path, encoding: 'utf-8')
        metadata = {}

        # Extract title
        if content =~ %r{<title>(.*?)</title>}mi
          metadata[:title] = ::Regexp.last_match(1).strip
        elsif content =~ %r{<h1>(.*?)</h1>}mi
          metadata[:title] = ::Regexp.last_match(1).strip
        end

        # Extract meta tags - improved regex to handle quotes properly
        content.scan(%r{<meta\s+name=["']?([^"'\s]+)["']?\s+content=["']?([^"']+)["']?\s*/?\s*>}i).each do |name, content|
          case name.downcase
          when 'author'
            metadata[:author] = content
          when 'description'
            metadata[:description] = content
          when 'keywords'
            metadata[:keywords] = content.split(',').map(&:strip)
          end
        end

        # Extract body content for language detection
        # Remove script and style tags, then extract text
        body_content = content.gsub(%r{<script[^>]*>.*?</script>}mi, '')
                              .gsub(%r{<style[^>]*>.*?</style>}mi, '')
        metadata[:content] = if body_content =~ %r{<body[^>]*>(.*?)</body>}mi
                               ::Regexp.last_match(1).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
                             elsif body_content =~ /<body[^>]*>(.*)/mi
                               ::Regexp.last_match(1).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
                             else
                               # Fallback: extract any text content
                               content.gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
                             end

        metadata
      rescue StandardError => e
        @logger.warn "Failed to extract HTML metadata: #{e.message}"
        {}
      end
    end
  end
end
