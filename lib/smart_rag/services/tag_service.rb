require_relative "../models/tag"
require_relative "../models/section_tag"
require_relative "../models/source_section"
require_relative "../errors"
require "smart_prompt"

module SmartRAG
  module Services
    # Service for managing tags, including generation, hierarchy, and content associations
    class TagService
      attr_reader :config, :smart_prompt_engine, :logger

      # Initialize the tag service
      # @param config [Hash] Configuration options
      # @option config [String] :config_path Path to smart_prompt config (default: config/llm_config.yml)
      # @option config [Integer] :max_retries Maximum retries for API calls (default: 3)
      # @option config [Integer] :timeout Timeout for API calls (default: 30)
      # @option config [Logger] :logger Logger instance (default: Logger.new(STDOUT))
      def initialize(config = {})
        config ||= {}
        @logger = Logger.new(STDOUT)
        @config = default_config.merge(config)
        @logger = @config[:logger] || @logger

        # Load workers
        workers_dir = File.join(File.dirname(__FILE__), "..", "..", "..", "workers")
        Dir.glob(File.join(workers_dir, "*.rb")).each { |file| require file }

        # Initialize SmartPrompt engine
        config_path = @config[:config_path] || "config/llm_config.yml"
        @smart_prompt_engine = SmartPrompt::Engine.new(config_path)
      rescue StandardError => e
        log_error("Failed to initialize TagService", e)
        raise
      end

      # Validate input for tag generation
      # @param text [String] The text to validate
      # @raise [ArgumentError] if text is nil or empty
      def validate_input!(text)
        raise ArgumentError, "Text cannot be empty" if text.to_s.strip.empty?
      end

      # Generate tags for text content using LLM
      # @param text [String] Text content to analyze
      # @param topic [String] Topic/context for the text (optional)
      # @param languages [Array<Symbol>] Target languages for tags (e.g., [:zh_cn, :en])
      # @param options [Hash] Additional options
      # @option options [Boolean] :include_category Include category tags (default: true)
      # @option options [Boolean] :include_content Include content tags (default: true)
      # @option options [Integer] :max_category_tags Maximum category tags (default: 5)
      # @option options [Integer] :max_content_tags Maximum content tags (default: 10)
      # @return [Hash] Generated tags structure with categories and content tags
      # @example
      #   generate_tags("Machine learning algorithms...", topic: "AI Research")
      #   # => {
      #   #   categories: ["Machine Learning", "Artificial Intelligence"],
      #   #   content_tags: ["Neural Networks", "Deep Learning", "Training Data"]
      #   # }
      def generate_tags(text, topic = nil, languages = [:zh_cn, :en], options = {})
        # Validate input - this will raise ArgumentError if empty, which is expected by tests
        validate_input!(text)

        # Truncate text if too long
        max_text_length = config[:max_text_length] || 4000
        truncated_text = text.length > max_text_length ? text[0...max_text_length] + "..." : text

        # Build prompt based on topic and options
        prompt = build_tag_generation_prompt(truncated_text, topic, languages, options)

        # Call LLM to generate tags (with error handling)
        response = call_llm_for_tags(prompt, options)

        # Parse and validate the response
        parse_generated_tags(response, languages)
      rescue ArgumentError
        # Re-raise ArgumentError as-is for empty text validation
        raise
      rescue StandardError => e
        log_error("Failed to generate tags", e)
        # Raise TagGenerationError instead of returning empty result
        raise ::SmartRAG::Errors::TagGenerationError, "Tag generation failed: #{e.message}"
      end

      # Batch generate tags for multiple sections
      # @param sections [Array<SourceSection>] Sections to generate tags for
      # @param topic [String] Topic/context for the content
      # @param languages [Array<Symbol>] Target languages for tags
      # @param options [Hash] Additional options
      # @return [Hash] Mapping of section_id to generated tags
      def batch_generate_tags(sections, topic = nil, languages = [:zh_cn, :en], options = {})
        raise ArgumentError, "Sections cannot be nil" unless sections
        return {} if sections.empty?

        logger.info "Generating tags for #{sections.size} sections"

        result = {}
        sections.each_with_index do |section, index|
          begin
            section_text = prepare_section_text(section)
            tags = generate_tags(section_text, topic, languages, options)
            result[section.id] = tags

            logger.info "Generated tags for section #{section.id} (#{index + 1}/#{sections.size})"
          rescue StandardError => e
            logger.error "Failed to generate tags for section #{section.id}: #{e.message}"
            result[section.id] = { categories: [], content_tags: [] }
          end
        end

        result
      rescue StandardError => e
        log_error("Failed to batch generate tags", e)
        raise ::SmartRAG::Errors::TagGenerationError, "Batch tag generation failed: #{e.message}"
      end

      # Find or create tags by names
      # @param tag_names [Array<String>] Tag names to find or create
      # @param parent_id [Integer] Parent tag ID for hierarchical tags
      # @param options [Hash] Additional options
      # @return [Array<Tag>] Array of tag objects
      def find_or_create_tags(tag_names, parent_id = nil, options = {})
        raise ArgumentError, "Tag names cannot be nil" unless tag_names
        return [] if tag_names.empty?

        # Ensure unique and clean tag names
        clean_names = tag_names.map { |name| clean_tag_name(name) }.uniq.compact

        # Process in transaction
        Models::Tag.db.transaction do
          clean_names.map do |name|
            Models::Tag.find_or_create(name, parent_id: parent_id)
          end
        end
      rescue StandardError => e
        log_error("Failed to find or create tags", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag creation failed: #{e.message}"
      end

      # Create hierarchical tags from nested structure
      # @param hierarchy [Hash] Tag hierarchy structure
      # @param parent_id [Integer] Parent tag ID (for recursive calls)
      # @return [Array<Tag>] Created tags
      # @example
      #   create_hierarchy({
      #     "Technology" => {
      #       "AI" => ["Machine Learning", "Deep Learning"],
      #       "Web" => ["Frontend", "Backend"]
      #     }
      #   })
      def create_hierarchy(hierarchy, parent_id = nil)
        raise ArgumentError, "Hierarchy cannot be nil" unless hierarchy
        return [] if hierarchy.empty?

        created_tags = []

        Models::Tag.db.transaction do
          hierarchy.each do |name, children|
            # Create current tag
            tag = Models::Tag.find_or_create(clean_tag_name(name), parent_id: parent_id)
            created_tags << tag

            # Recursively create children
            if children.is_a?(Hash)
              # Nested structure
              created_tags.concat(create_hierarchy(children, tag.id))
            elsif children.is_a?(Array)
              # Array of child names
              child_tags = find_or_create_tags(children, tag.id)
              created_tags.concat(child_tags)
            end
          end
        end

        created_tags.uniq
      rescue StandardError => e
        log_error("Failed to create tag hierarchy", e)
        raise ::SmartRAG::Errors::DatabaseError, "Hierarchy creation failed: #{e.message}"
      end

      # Associate tags with a section
      # @param section [SourceSection] The section to tag
      # @param tags [Array<Tag>] Tags to associate
      # @param options [Hash] Options (e.g., replace_existing: false)
      # @return [Array<SectionTag>] Created associations
      def associate_with_section(section, tags, options = {})
        raise ArgumentError, "Section cannot be nil" unless section
        raise ArgumentError, "Tags cannot be nil" unless tags
        return [] if tags.empty?

        # Ensure all tags exist and are Tag objects
        begin
          tag_objects = ensure_tag_objects(tags)
        rescue ArgumentError => e
          raise ArgumentError, e.message
        end

        Models::Tag.db.transaction do
          # Remove existing tags if replace option is set
          if options[:replace_existing]
            section.remove_all_tags
          end

          # Create associations
          tag_objects.map do |tag|
            begin
              section.add_tag(tag)
              Models::SectionTag.find(section_id: section.id, tag_id: tag.id)
            rescue Sequel::UniqueConstraintViolation
              # Already associated, find existing
              Models::SectionTag.find(section_id: section.id, tag_id: tag.id)
            end
          end.compact
        end
      rescue ArgumentError
        raise
      rescue StandardError => e
        log_error("Failed to associate tags with section", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag association failed: #{e.message}"
      end

      # Associate tags with multiple sections (batch)
      # @param sections [Array<SourceSection>] Sections to tag
      # @param tags [Array<Tag>] Tags to associate
      # @param options [Hash] Association options
      def batch_associate_with_sections(sections, tags, options = {})
        raise ArgumentError, "Sections cannot be nil" unless sections
        raise ArgumentError, "Tags cannot be nil" unless tags
        return [] if sections.empty? || tags.empty?

        tag_objects = ensure_tag_objects(tags)
        results = []

        Models::Tag.db.transaction do
          sections.each do |section|
            begin
              associations = associate_with_section(section, tag_objects, options)
              results.concat(associations)
            rescue StandardError => e
              logger.error "Failed to associate tags with section #{section.id}: #{e.message}"
            end
          end
        end

        results
      rescue StandardError => e
        log_error("Failed to batch associate tags", e)
        raise ::SmartRAG::Errors::DatabaseError, "Batch association failed: #{e.message}"
      end

      # Remove tag associations from a section
      # @param section [SourceSection] The section
      # @param tags [Array<Tag>] Tags to remove (if nil, remove all)
      # @return [Integer] Number of removed associations
      def dissociate_from_section(section, tags = nil)
        raise ArgumentError, "Section cannot be nil" unless section

        if tags.nil?
          # Remove all tags
          removed_count = section.tags.count
          section.remove_all_tags
          removed_count
        else
          # Remove specific tags
          begin
            tag_objects = ensure_tag_objects(tags)
          rescue ArgumentError => e
            raise ArgumentError, e.message
          end

          removed_count = 0

          Models::Tag.db.transaction do
            tag_objects.each do |tag|
              if section.tags.include?(tag)
                section.remove_tag(tag)
                removed_count += 1
              end
            end
          end

          removed_count
        end
      rescue ArgumentError
        raise
      rescue StandardError => e
        log_error("Failed to dissociate tags from section", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag dissociation failed: #{e.message}"
      end

      # Get sections by tag with optional filters
      # @param tag [Tag] The tag to filter by
      # @param options [Hash] Filter options
      # @return [Array<SourceSection>] Filtered sections
      def get_sections_by_tag(tag, options = {})
        raise ArgumentError, "Tag cannot be nil" unless tag

        query = tag.sections_dataset

        # Apply filters
        if options[:document_id]
          query = query.where(document_id: options[:document_id])
        end

        if options[:has_embedding]
          query = query.association_join(:embedding)
        end

        if options[:limit]
          query = query.limit(options[:limit])
        end

        query.all
      rescue StandardError => e
        log_error("Failed to get sections by tag", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag query failed: #{e.message}"
      end

      # Get tags for a section
      # @param section [SourceSection] The section
      # @param include_ancestors [Boolean] Include ancestor tags
      # @return [Array<Tag>] Tags for the section
      def get_tags_for_section(section, include_ancestors: false)
        raise ArgumentError, "Section cannot be nil" unless section

        base_tags = section.tags

        return base_tags unless include_ancestors

        # Include ancestor tags in hierarchy
        all_tags = base_tags.dup
        base_tags.each do |tag|
          all_tags.concat(tag.ancestors)
        end

        all_tags.uniq
      rescue StandardError => e
        log_error("Failed to get tags for section", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag query failed: #{e.message}"
      end

      # Search tags by name with optional filters
      # @param query [String] Search query
      # @param options [Hash] Search options
      # @option options [Integer] :limit Maximum results (default: 20)
      # @option options [Boolean] :include_usage Include usage count
      # @return [Array<Tag>] Matching tags
      def search_tags(query, options = {})
        raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?

        limit = options[:limit] || 20
        search_pattern = "%#{query.downcase}%"

        base_query = Models::Tag.where(Sequel.ilike(:name, search_pattern))

        if options[:include_usage]
          base_query = Models::Tag.with_section_count
            .where(Sequel.ilike(:name, search_pattern))
        end

        base_query.limit(limit).all
      rescue ArgumentError
        raise
      rescue StandardError => e
        log_error("Failed to search tags", e)
        raise ::SmartRAG::Errors::DatabaseError, "Tag search failed: #{e.message}"
      end

      # Get popular tags
      # @param limit [Integer] Number of results (default: 20)
      # @return [Array<Hash>] Popular tags with usage count
      def get_popular_tags(limit = 20)
        Models::Tag.popular(limit: limit)
      rescue StandardError => e
        log_error("Failed to get popular tags", e)
        raise ::SmartRAG::Errors::DatabaseError, "Popular tags query failed: #{e.message}"
      end

      # Get tag hierarchy tree
      # @return [Array<Hash>] Hierarchical tag structure
      def get_tag_hierarchy
        Models::Tag.hierarchy
      rescue StandardError => e
        log_error("Failed to get tag hierarchy", e)
        raise ::SmartRAG::Errors::DatabaseError, "Hierarchy query failed: #{e.message}"
      end

      private

      def build_tag_generation_prompt(text, topic, languages, options)
        max_category_tags = options[:max_category_tags] || 3
        max_content_tags = options[:max_content_tags] || 5
        include_category = options.fetch(:include_category, true)
        include_content = options.fetch(:include_content, true)

        prompts = []

        languages.each do |lang|
          case lang.to_s
          when "zh"
            prompts << build_chinese_prompt(text, topic, max_category_tags, max_content_tags, include_category, include_content)
          when "en"
            prompts << build_english_prompt(text, topic, max_category_tags, max_content_tags, include_category, include_content)
          else
            logger.warn "Unsupported language: #{lang}, skipping"
          end
        end

        prompts.join("\n\n---\n\n")
      end

      def build_chinese_prompt(text, topic, max_category_tags, max_content_tags, include_category, include_content)
        prompt = "分析以下文本并生成标签：\n\n"
        prompt += "文本内容：\n#{text}\n\n"
        prompt += "主题：#{topic}\n\n" if topic

        prompt += "要求：\n"

        if include_category
          prompt += "1. 生成#{max_category_tags}个以内的高层级分类标签（如：人工智能、机器学习、深度学习等）\n"
        end

        if include_content
          prompt += "#{include_category ? "2" : "1"}. 生成#{max_content_tags}个以内的具体内容标签（描述文本的关键概念、技术、方法等）\n"
        end

        prompt += "\n"
        prompt += "以下列JSON格式输出：\n"
        prompt += "{\"categories\": [...], \"content_tags\": [...]}\n"
        prompt += "只输出JSON，不要额外解释。"

        prompt
      end

      def build_english_prompt(text, topic, max_category_tags, max_content_tags, include_category, include_content)
        prompt = "Analyze the following text and generate tags:\n\n"
        prompt += "Text content:\n#{text}\n\n"
        prompt += "Topic: #{topic}\n\n" if topic

        prompt += "Requirements:\n"

        if include_category
          prompt += "1. Generate up to #{max_category_tags} high-level category tags (e.g., Artificial Intelligence, Machine Learning, Deep Learning)\n"
        end

        if include_content
          prompt += "#{include_category ? "2" : "1"}. Generate up to #{max_content_tags} specific content tags (describing key concepts, techniques, methods from the text)\n"
        end

        prompt += "\n"
        prompt += "Output in the following JSON format:\n"
        prompt += '{"categories": [...], "content_tags": [...]}' + "\n"
        prompt += "Output only JSON, no additional explanation."

        prompt
      end

      def call_llm_for_tags(prompt, options)
        max_retries = options[:retries] || config[:max_retries]
        timeout = options[:timeout] || config[:timeout]

        with_retry(max_retries: max_retries, timeout: timeout) do
          result = smart_prompt_engine.call_worker(:analyze_content, { content: prompt })
          raise "No response from LLM" unless result

          result
        end
      rescue StandardError => e
        logger.error "LLM call failed: #{e.message}"
        raise
      end

      def parse_generated_tags(response, languages)
        # Handle nil or empty response
        return { categories: [], content_tags: [] } if response.nil? || response.empty?

        # Try to parse as JSON first
        begin
          parsed = JSON.parse(response.dig("choices", 0, "message", "content"))
          return {
                   categories: (parsed["categories"] || []).map { |c| clean_tag_name(c) }.compact,
                   content_tags: (parsed["content_tags"] || []).map { |c| clean_tag_name(c) }.compact,
                 }
        rescue JSON::ParserError
          # Fallback to manual parsing
          logger.warn "Failed to parse LLM response as JSON, attempting manual parsing"
        end

        # Manual parsing for malformed responses
        categories = []
        content_tags = []

        # Look for JSON-like patterns
        if response =~ /\{\s*"categories"\s*:\s*\[([^\]]+)\]/
          categories_str = $1
          categories = categories_str.scan(/"([^"]+)"/).flatten
        end

        if response =~ /"content_tags"\s*:\s*\[([^\]]+)\]/
          content_str = $1
          content_tags = content_str.scan(/"([^"]+)"/).flatten
        end

        # If still no results, try to extract quoted strings
        if categories.empty? && content_tags.empty?
          all_quotes = response.scan(/"([^"]+)"/).flatten
          if all_quotes.any?
            # Heuristic: first few are categories, rest are content tags
            midpoint = [all_quotes.length / 3, 2].max
            categories = all_quotes[0...midpoint]
            content_tags = all_quotes[midpoint..-1]
          end
        end

        {
          categories: categories.map { |c| clean_tag_name(c) }.compact,
          content_tags: content_tags.map { |c| clean_tag_name(c) }.compact,
        }
      end

      def prepare_section_text(section)
        parts = []
        parts << "Section #{section.section_number}: #{section.section_title}" if section.section_number && section.section_title
        parts << section.section_title if section.section_title && parts.empty?
        parts << section.content

        parts.compact.join("\n\n")
      end

      def ensure_tag_objects(tags)
        tags.map do |tag|
          case tag
          when Models::Tag
            tag
          when Integer
            Models::Tag.find(id: tag) || raise(ArgumentError, "Tag not found: #{tag}")
          when String
            Models::Tag.find(name: tag) || raise(ArgumentError, "Tag not found: #{tag}")
          else
            # Support RSpec mocks and other test doubles
            if tag.respond_to?(:id) && tag.respond_to?(:name)
              tag
            else
              raise ArgumentError, "Invalid tag type: #{tag.class}"
            end
          end
        end
      end

      def clean_tag_name(name)
        return nil if name.nil?

        cleaned = name.to_s.strip
        return nil if cleaned.empty?

        # Normalize the tag name
        return cleaned if cleaned.match?(/\p{Han}/)
        return cleaned.gsub(/[^\w\s\-]/, " ").gsub(/\s+/, " ").strip
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
            sleep(2 ** attempt) if attempt < max_retries - 1
          end
        end

        raise last_exception
      end

      def log_error(message, exception)
        logger.error "#{message}: #{exception.message}"
        logger.error exception.backtrace.join("\n")
      end

      def default_config
        {
          config_path: "config/llm_config.yml",
          max_retries: 3,
          timeout: 30,
          batch_size: 50,
          max_text_length: 4000,
          logger: Logger.new(STDOUT),
        }
      end
    end
  end
end
