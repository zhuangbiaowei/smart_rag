# frozen_string_literal: true

require 'unit_spec_helper'
require 'smart_rag'

RSpec.describe 'SmartRAG media API routing' do
  let(:rag) do
    SmartRAG::SmartRAG.allocate.tap do |instance|
      instance.instance_variable_set(:@logger, Logger.new(nil))
      instance.instance_variable_set(:@document_processor, document_processor)
    end
  end
  let(:document) { double('document', id: 12, metadata: { media_type: 'document', schema_version: 1 }.to_json) }
  let(:document_processor) do
    double('document processor', create_document: { document: document, sections: [double('section')] })
  end

  it 'classifies add_document resources as document media' do
    result = rag.add_document('/tmp/report.pdf', title: 'Report')

    expect(result).to include(document_id: 12, media_type: 'document', status: 'success', warnings: [])
    expect(document_processor).to have_received(:create_document).with(
      '/tmp/report.pdf',
      hash_including(title: 'Report', metadata: hash_including(media_type: 'document', schema_version: 1))
    )
  end

  it 'routes auto-detected document files to add_document' do
    allow(rag).to receive(:add_document).and_return(status: 'success', media_type: 'document')

    result = rag.add_media('/tmp/report.pdf', tags: ['report'])

    expect(result[:media_type]).to eq('document')
    expect(rag).to have_received(:add_document).with('/tmp/report.pdf', tags: ['report'])
  end

  it 'routes explicit document URLs to add_document' do
    allow(rag).to receive(:add_document).and_return(status: 'success', media_type: 'document')

    rag.add_media('https://example.com/download', media_type: 'document', title: 'Remote report')

    expect(rag).to have_received(:add_document).with(
      'https://example.com/download', media_type: 'document', title: 'Remote report'
    )
  end

  it 'routes document URLs with query strings by their path extension' do
    allow(rag).to receive(:add_document).and_return(status: 'success', media_type: 'document')

    rag.add_media('https://example.com/report.pdf?download=1')

    expect(rag).to have_received(:add_document).with('https://example.com/report.pdf?download=1', {})
  end

  it 'lets system document metadata override string-keyed user values without duplicate keys' do
    rag.add_document('/tmp/report.pdf', metadata: { 'media_type' => 'image', 'owner' => 'docs' })

    expect(document_processor).to have_received(:create_document).with(
      '/tmp/report.pdf',
      hash_including(metadata: { media_type: 'document', owner: 'docs', schema_version: 1 })
    )
  end
end
