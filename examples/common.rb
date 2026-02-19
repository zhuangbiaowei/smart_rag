#!/usr/bin/env ruby
# frozen_string_literal: true

require "logger"
require "dotenv"
require_relative "../lib/smart_rag"

module Examples
  module Common
    module_function

    def load_env!
      Dotenv.load(".env.local", ".env")
    rescue StandardError
      # Keep examples usable even if dotenv loading fails unexpectedly.
    end

    def default_config
      load_env!
      {
        database: {
          adapter: "postgresql",
          host: ENV["SMARTRAG_DB_HOST"] || "localhost",
          port: (ENV["SMARTRAG_DB_PORT"] || "5432").to_i,
          database: ENV["SMARTRAG_DB_NAME"] || "smart_rag_development",
          user: ENV["SMARTRAG_DB_USER"] || "smart_rag_user",
          password: ENV["SMARTRAG_DB_PASSWORD"],
        },
        llm: {
          provider: ENV["SMARTRAG_LLM_PROVIDER"] || ENV["LLM_PROVIDER"] || "openai",
          api_key: ENV["OPENAI_API_KEY"] || ENV["LLM_API_KEY"] || "ollama-local",
          endpoint: ENV["LLM_ENDPOINT"] || "http://localhost:11434/v1/chat/completions",
          model: ENV["LLM_MODEL"] || "qwen3",
        },
      }
    end

    def build_client(log_level: Logger::INFO)
      client = SmartRAG::SmartRAG.new(default_config)
      client.logger = Logger.new($stdout)
      client.logger.level = log_level
      client
    end

    def print_header(title)
      puts "\n#{'=' * 72}"
      puts title
      puts "=" * 72
    end

    def print_json(name, data)
      require "json"
      puts "#{name}:"
      puts JSON.pretty_generate(data)
    end
  end
end
