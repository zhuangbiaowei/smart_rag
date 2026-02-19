#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "common"

include Examples::Common

print_header("Quick Start")
smart_rag = build_client

stats = smart_rag.statistics
puts "SmartRAG initialized."
puts "Documents in DB: #{stats[:document_count]}"

query = ARGV[0] || "machine learning algorithms"
results = smart_rag.search(
  query,
  search_type: "hybrid",
  limit: 5,
  include_content: true,
)

print_header("First Search: #{query}")
results.fetch(:results, []).each_with_index do |result, idx|
  score = result[:combined_score] || result[:similarity] || 0.0
  puts "#{idx + 1}. #{result[:section_title]} (score: #{score.round(3)})"
  next unless result[:content]

  preview = result[:content][0, 120].to_s.gsub(/\s+/, " ")
  puts "   #{preview}..."
end

