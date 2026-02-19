#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "common"

include Examples::Common

print_header("Document Management")
smart_rag = build_client

document_path = ARGV[0]
if document_path.nil? || document_path.strip.empty?
  warn "Usage: ruby examples/02_document_management.rb /path/to/document.md"
  exit 1
end

add_result = smart_rag.add_document(
  document_path,
  title: File.basename(document_path),
  generate_embeddings: true,
  generate_tags: true,
  tags: ["example", "usage_examples"],
  metadata: { source: "examples/02_document_management.rb" },
)

print_json("Add Result", add_result)

document_id = add_result[:document_id]
detail = smart_rag.get_document(document_id)
print_json("Document Detail", detail || {})

list = smart_rag.list_documents(page: 1, per_page: 10, search: File.basename(document_path))
print_json("Document List", list)

# Pass DELETE=1 to demonstrate cleanup:
# DELETE=1 ruby examples/02_document_management.rb test/python_basics.md
if ENV["DELETE"] == "1"
  delete_result = smart_rag.remove_document(document_id)
  print_json("Delete Result", delete_result)
end

