#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "common"

include Examples::Common

print_header("Search Operations")
smart_rag = build_client

query = ARGV[0] || "deep learning applications in healthcare"

hybrid = smart_rag.search(
  query,
  search_type: "hybrid",
  limit: 5,
  alpha: 0.7,
  include_metadata: true,
)
print_json("Hybrid Search Metadata", hybrid[:metadata] || {})

vector = smart_rag.vector_search(
  "neural network architectures",
  limit: 5,
  include_content: false,
)
print_json("Vector Search Metadata", vector[:metadata] || {})

fulltext = smart_rag.fulltext_search(
  '"deep reinforcement learning"',
  limit: 5,
)
print_json("Fulltext Search Metadata", fulltext[:metadata] || {})

multilingual_queries = [
  ["zh_cn", "人工智能应用"],
  ["ja", "機械学習アルゴリズム"],
  ["ko", "딥러닝 모델"],
  ["auto", "AI和机器学习的发展"],
]

multilingual_queries.each do |language, q|
  result = smart_rag.search(q, search_type: "hybrid", language: language, limit: 3)
  puts "[#{language}] #{q} -> #{result.fetch(:results, []).length} results"
end

