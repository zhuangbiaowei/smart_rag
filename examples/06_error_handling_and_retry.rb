#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "common"

include Examples::Common

class RetryableSmartRAG
  def initialize(smart_rag, retries: 3, base_interval: 0.5)
    @smart_rag = smart_rag
    @retries = retries
    @base_interval = base_interval
  end

  def add_document(path, **options)
    with_retry(on: [SmartRAG::Errors::EmbeddingGenerationError]) do
      @smart_rag.add_document(path, options)
    end
  end

  def search(query, **options)
    with_retry(on: [SmartRAG::Errors::DatabaseError]) do
      @smart_rag.search(query, options)
    end
  end

  private

  def with_retry(on:)
    attempt = 0
    begin
      attempt += 1
      yield
    rescue *on => e
      raise e if attempt >= @retries

      sleep @base_interval * (2**(attempt - 1))
      retry
    end
  end
end

print_header("Error Handling And Retry")
smart_rag = build_client
retryable = RetryableSmartRAG.new(smart_rag)

begin
  # Intentional invalid call to show argument error handling.
  smart_rag.search("", search_type: "hybrid")
rescue SmartRAG::Errors::InvalidParameterError, SmartRAG::Errors::InvalidQueryError, ArgumentError => e
  puts "Argument error: #{e.message}"
rescue SmartRAG::Errors::DatabaseError => e
  puts "Database error: #{e.message}"
rescue SmartRAG::Errors::EmbeddingGenerationError => e
  puts "Embedding generation error: #{e.message}"
rescue SmartRAG::Errors::DocumentProcessingError => e
  puts "Document processing error: #{e.message}"
rescue StandardError => e
  puts "Unexpected error: #{e.class} - #{e.message}"
end

safe_query = ARGV[0] || "machine learning"
safe_result = retryable.search(safe_query, search_type: "hybrid", limit: 5)
puts "Retry search result count: #{safe_result.fetch(:results, []).length}"
