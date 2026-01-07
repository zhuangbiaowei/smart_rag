require 'yaml'
require 'erb'

module SmartRAG
  class Config
    class << self
      def load(file_path = nil)
        # If file_path is a Hash, return it directly (already a config hash)
        return symbolize_keys(file_path) if file_path.is_a?(Hash)

        file_path ||= default_config_path

        unless File.exist?(file_path)
          raise "Configuration file not found: #{file_path}"
        end

        yaml_content = File.read(file_path)
        config = YAML.safe_load(
          ERB.new(yaml_content).result,
          permitted_classes: [Symbol, Time]
        )

        # Convert string keys to symbols for consistency
        config = symbolize_keys(config) if config.is_a?(Hash)

        validate_config(config)
        config
      end

      def load_database_config(env = nil)
        env ||= ENV['RACK_ENV'] || 'development'
        env = env.to_sym if env.respond_to?(:to_sym)
        database_config_path = File.join(config_dir, 'database.yml')

        unless File.exist?(database_config_path)
          # Fallback to main config
          config = load
          return config[:database] if config[:database]

          raise "Database configuration file not found: #{database_config_path}"
        end

        yaml_content = File.read(database_config_path)
        config = YAML.safe_load(
          ERB.new(yaml_content).result,
          permitted_classes: [Symbol]
        )

        # Convert string keys to symbols for consistency
        config = symbolize_keys(config) if config.is_a?(Hash)

        config[env] || config[:default] || config
      end

      def load_fulltext_config
        fulltext_config_path = File.join(config_dir, 'fulltext_search.yml')

        unless File.exist?(fulltext_config_path)
          # Fallback to main config
          config = load
          return config[:fulltext_search] || {} if config[:fulltext_search]

          return {}
        end

        yaml_content = File.read(fulltext_config_path)
        config = YAML.safe_load(
          ERB.new(yaml_content).result,
          permitted_classes: [Symbol]
        ) || {}

        # Convert string keys to symbols for consistency
        symbolize_keys(config) if config.is_a?(Hash)
      end

      private

      def default_config_path
        @default_config_path ||= File.join(config_dir, 'smart_rag.yml')
      end

      def config_dir
        @config_dir ||= File.join(__dir__, '..', '..', 'config')
      end

      def validate_config(config)
        return unless config.is_a?(Hash)

        # Validate required sections
        unless config[:database]
          raise "Missing required 'database' configuration"
        end

        # Validate embedding configuration
        if config[:embedding]
          unless config[:embedding][:provider]
            puts "Warning: Missing embedding provider configuration"
          end

          unless config[:embedding][:dimensions]
            puts "Warning: Missing embedding dimensions, defaulting to 1024"
            config[:embedding][:dimensions] = 1024
          end
        end

        # Validate fulltext search configuration
        if config[:fulltext_search]
          # Check for supported languages
          supported_langs = ['en', 'zh', 'ja', 'ko', 'default']
        end

        true
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          key = key.to_sym if key.respond_to?(:to_sym)
          value = symbolize_keys(value) if value.is_a?(Hash)
          result[key] = value
        end
      end
    end
  end
end
