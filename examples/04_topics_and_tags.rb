#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "common"

include Examples::Common

print_header("Topics And Tags")
smart_rag = build_client

topic = smart_rag.create_topic(
  "AI in Healthcare",
  "Applications of AI in medical diagnosis and treatment",
  tags: ["ai", "healthcare", "diagnosis"],
  document_ids: [],
)
print_json("Created Topic", topic)

topic_detail = smart_rag.get_topic(topic[:id])
print_json("Topic Detail", topic_detail || {})

all_topics = smart_rag.list_topics(page: 1, per_page: 20)
puts "Topic count on page: #{all_topics.fetch(:topics, []).length}"

recommendations = smart_rag.get_topic_recommendations(topic[:id], limit: 5)
print_json("Topic Recommendations", recommendations)

sample_text = <<~TEXT
  Machine learning is a subset of artificial intelligence that enables systems
  to learn and improve from experience without explicit programming.
TEXT

tags = smart_rag.generate_tags(sample_text, context: "AI introduction", max_tags: 5)
print_json("Generated Tags", tags)

tag_page = smart_rag.list_tags(page: 1, per_page: 20)
puts "Tag count on page: #{tag_page.fetch(:tags, []).length}"

