# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))

require 'smart_rag'
require 'smart_rag/http_app'
require 'smart_rag/http_access_policy'

config_path = ENV['SMARTRAG_CONFIG_PATH']
rag = SmartRAG::SmartRAG.new(SmartRAG::Config.load(config_path))
access_policy = SmartRAG::HttpAccessPolicy.new(db: SmartRAG.db, config: rag.config[:http_auth] || {})

# Applications can replace this file and inject server-side OCR, vision, and
# transcription adapters through HttpApp's extractors: option.
run SmartRAG::HttpApp.new(rag: rag, access_policy: access_policy)
