require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # TextSearchConfig model for language-specific search configurations
    class TextSearchConfig < Sequel::Model(:text_search_configs)
      include FactoryBotHelpers
      plugin :validation_helpers
      # This model uses text_search_configs table with language_code as PK
      set_primary_key :language_code

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Validation
      def validate
        super
        validates_presence [:language_code, :config_name]
        validates_length_range 2..10, :language_code
        validates_format /\A[a-zA-Z0-9_\-]+\z/, :language_code, message: 'can only contain letters, numbers, hyphens, and underscores'
      end

      # Class methods
      class << self
        # Get config by language code
        def for_language(lang_code)
          find(language_code: lang_code)
        end

        # Get all installed configs
        def installed
          where(is_installed: true)
        end

        # Get config names by language
        def config_name_for(lang_code)
          config = for_language(lang_code)
          config&.config_name
        end

        # Get fallback config for language
        def fallback_config(lang_code)
          # Try exact match first
          return for_language(lang_code) if for_language(lang_code)

          # Try language prefix (e.g., 'en' for 'en_US')
          base_lang = lang_code.to_s.split('_').first
          return for_language(base_lang) if for_language(base_lang)

          # Try 'default' config
          return for_language('default') if for_language('default')

          # Fallback to 'simple'
          new(language_code: 'simple', config_name: 'pg_catalog.simple', is_installed: true)
        end

        # Get all available languages
        def available_languages
          installed.select_map(:language_code)
        end

        # Get config name for tsquery/tsvector
        def ts_config(lang_code)
          config = fallback_config(lang_code)
          config.config_name
        end

        # Batch create/update configs
        def upsert_all(configs)
          configs.each do |config_data|
            if existing = find(language_code: config_data[:language_code])
              existing.update(config_data)
            else
              create(config_data)
            end
          end
        end

        # Install a config (if possible)
        def install_config(lang_code, config_name)
          config = find_or_create(language_code: lang_code, config_name: config_name, is_installed: true)

          # Try to create extension in database
          begin
            db.run "CREATE EXTENSION IF NOT EXISTS #{config_name}" if config_name.include?('.')
          rescue Sequel::DatabaseError => e
            # If extension creation fails, mark as not installed
            config.update(is_installed: false)
            puts "Warning: Could not install search config '#{config_name}': #{e.message}"
          end

          config
        end
      end

      # Instance methods

      # Check if config is installed
      def installed?
        is_installed
      end

      # Install this config
      def install
        begin
          db.run "CREATE EXTENSION IF NOT EXISTS #{config_name}" if config_name.include?('.')
          update(is_installed: true)
        rescue Sequel::DatabaseError => e
          update(is_installed: false)
          puts "Warning: Could not install search config '#{config_name}': #{e.message}"
          false
        end
      end

      # Uninstall this config
      def uninstall
        if config_name.include?('.')
          begin
            db.run "DROP EXTENSION IF EXISTS #{config_name}"
          rescue Sequel::DatabaseError => e
            puts "Warning: Could not uninstall search config '#{config_name}': #{e.message}"
          end
        end
        update(is_installed: false)
      end

      # Get language display name
      def display_name
        language_names = {
          'en' => 'English',
          'zh' => 'Chinese',
          'ja' => 'Japanese',
          'ko' => 'Korean',
          'simple' => 'Simple',
          'jieba' => 'Chinese (Jieba)',
          'en_us' => 'English (US)',
          'en_gb' => 'English (UK)',
          'zh_cn' => 'Chinese (Simplified)',
          'zh_tw' => 'Chinese (Traditional)',
          'ja_jp' => 'Japanese',
          'ko_kr' => 'Korean'
        }

        language_names[language_code] || language_code.upcase
      end

      # Config info
      def info
        {
          language_code: language_code,
          config_name: config_name,
          installed: installed?,
          display_name: display_name
        }
      end

      # String representation
      def to_s
        "<TextSearchConfig: #{language_code} - #{config_name}#{installed? ? '' : ' (not installed)'}>"
      end
    end
  end
end
