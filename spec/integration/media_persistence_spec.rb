# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'smart_rag'
require 'smart_rag/core/document_processor'
require_relative '../support/database_helpers'

RSpec.describe 'media metadata persistence', type: :integration do
  before(:all) do
    @db = Sequel.connect(DatabaseHelpers.test_db_config)
    SmartRAG.db = @db
    SmartRAG::Models.db = @db
    SmartRAG::Models::SourceDocument.set_dataset(@db[:source_documents])
    SmartRAG::Models::SourceSection.set_dataset(@db[:source_sections])
  end

  after(:all) do
    @db&.disconnect
  end

  around do |example|
    @db.transaction(rollback: :always) { example.run }
  end

  let(:processor) { SmartRAG::Core::DocumentProcessor.new(logger: Logger.new(nil)) }

  it 'stores section-level video positioning metadata in JSONB' do
    document = SmartRAG::Models::SourceDocument.create(
      title: 'Video', url: "video-#{Process.pid}-#{rand(10_000)}.mp4",
      source_type: 'file', metadata: { media_type: 'video' }.to_json
    )

    sections = processor.save_sections(
      document,
      [{ title: 'Video transcript 00:00:05', content: 'Open settings',
         metadata: { media_type: 'video', extraction_kind: 'transcript', start_ms: 5000, end_ms: 9000 } }]
    )

    stored = JSON.parse(SmartRAG.db[:source_sections].where(id: sections.first.id).get(:metadata))
    expect(stored).to include(
      'media_type' => 'video', 'extraction_kind' => 'transcript', 'start_ms' => 5000, 'end_ms' => 9000
    )
  end

  it 'gives pre-existing style sections an empty metadata object' do
    document = SmartRAG::Models::SourceDocument.create(
      title: 'Legacy', url: "legacy-#{Process.pid}-#{rand(10_000)}.txt"
    )
    section_id = SmartRAG.db[:source_sections].insert(document_id: document.id, content: 'legacy content')

    stored = SmartRAG.db[:source_sections].where(id: section_id).get(:metadata)
    expect(JSON.parse(stored)).to eq({})
  end
end
