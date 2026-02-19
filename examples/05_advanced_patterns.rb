#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require_relative "common"

include Examples::Common

class ContextualSearch
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def search_with_context(query, user_context = {})
    enhanced_query = enhance_query(query, user_context)
    filters = build_filters(user_context)

    @smart_rag.search(
      enhanced_query,
      search_type: "hybrid",
      limit: 10,
      filters: filters,
    )
  end

  private

  def enhance_query(query, context)
    case context[:domain]
    when "healthcare"
      "#{query} medical clinical"
    when "finance"
      "#{query} finance banking"
    else
      query
    end
  end

  def build_filters(context)
    filters = {}
    filters[:document_ids] = context[:document_ids] if context[:document_ids]
    filters[:tag_ids] = context[:preferred_tags] if context[:preferred_tags]
    filters
  end
end

class SearchPipeline
  def initialize(smart_rag)
    @smart_rag = smart_rag
    @processors = []
  end

  def add_processor(&block)
    @processors << block
    self
  end

  def search(query, options = {})
    results = @smart_rag.search(query, options)
    @processors.each { |processor| results = processor.call(results, query, options) }
    results
  end
end

class MemorySearchCache
  def initialize(ttl_seconds: 300)
    @ttl_seconds = ttl_seconds
    @store = {}
  end

  def fetch(query, options)
    key = cache_key(query, options)
    cached = @store[key]
    if cached && cached[:expires_at] > Time.now
      return cached[:payload]
    end

    payload = yield
    @store[key] = { payload: payload, expires_at: Time.now + @ttl_seconds }
    payload
  end

  private

  def cache_key(query, options)
    Digest::MD5.hexdigest("#{query}:#{options.sort_by { |k, _| k.to_s }.to_h.to_json}")
  end
end

class QASystem
  def initialize(smart_rag)
    @smart_rag = smart_rag
  end

  def answer(question, context_limit: 5)
    search_results = @smart_rag.search(
      question,
      search_type: "hybrid",
      limit: context_limit,
      include_content: true,
    )
    results = search_results.fetch(:results, [])

    {
      question: question,
      answer: generate_answer(results),
      sources: results.map { |r| { section_id: r[:section_id], title: r[:section_title] } },
      confidence: results.empty? ? 0.0 : [results.first[:combined_score].to_f, 1.0].min,
    }
  end

  private

  def generate_answer(results)
    return "I do not have enough information in the current knowledge base." if results.empty?

    context = results.map { |r| r[:content].to_s }.join("\n---\n")
    "Draft answer from retrieved context: #{context[0, 400]}..."
  end
end

print_header("Advanced Patterns")
smart_rag = build_client

contextual = ContextualSearch.new(smart_rag)
contextual_results = contextual.search_with_context(
  "risk assessment",
  domain: "finance",
  document_ids: [],
  preferred_tags: [],
)
puts "Contextual search results: #{contextual_results.fetch(:results, []).length}"

pipeline = SearchPipeline.new(smart_rag)
pipeline.add_processor do |results, _query, options|
  min_score = options[:min_score] || 0.5
  results[:results] = results.fetch(:results, []).select do |r|
    (r[:combined_score] || r[:similarity] || 0.0) >= min_score
  end
  results
end
pipeline_results = pipeline.search("neural networks", search_type: "hybrid", limit: 20, min_score: 0.7)
puts "Pipeline filtered results: #{pipeline_results.fetch(:results, []).length}"

cache = MemorySearchCache.new(ttl_seconds: 600)
cached_1 = cache.fetch("deep learning", { limit: 5 }) { smart_rag.search("deep learning", limit: 5) }
cached_2 = cache.fetch("deep learning", { limit: 5 }) { smart_rag.search("deep learning", limit: 5) }
puts "Cache demo result sizes: #{cached_1.fetch(:results, []).length}, #{cached_2.fetch(:results, []).length}"

qa = QASystem.new(smart_rag)
qa_response = qa.answer("What are common applications of transformers in NLP?", context_limit: 3)
print_json("Q&A Response", qa_response)

