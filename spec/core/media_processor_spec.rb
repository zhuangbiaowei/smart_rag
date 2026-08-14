# frozen_string_literal: true

require 'unit_spec_helper'
require 'tempfile'
require 'smart_rag/core/media_processor'

RSpec.describe SmartRAG::Core::MediaProcessor do
  let(:file) do
    Tempfile.new(['meeting', '.wav']).tap do |item|
      item.write('audio bytes')
      item.close
    end
  end
  let(:document_class) { double('document class', db: db) }
  let(:document) do
    double('document', id: 7).tap do |item|
      allow(item).to receive(:class).and_return(document_class)
      allow(item).to receive(:set_download_state)
    end
  end
  let(:dataset) { double('dataset', select_map: [], delete: 0) }
  let(:db) do
    double('db').tap do |database|
      allow(database).to receive(:transaction).and_yield
      allow(database).to receive(:[]).and_return(dataset)
      allow(database).to receive(:table_exists?).and_return(false)
      allow(dataset).to receive(:where).and_return(dataset)
    end
  end
  let(:document_processor) do
    double('document processor').tap do |processor|
      allow(processor).to receive(:create_or_update_document).and_return(document)
      allow(processor).to receive(:chunk_content).and_return([{ title: 'meeting', content: 'Q3 roadmap' }])
      allow(processor).to receive(:save_sections).and_return([double('section')])
    end
  end
  let(:metadata_extractor) do
    double('metadata extractor', extract: {
      media_type: 'audio', media: SmartRAG::Core::MediaMetadataExtractor::DEFAULT_MEDIA.dup, warnings: []
    })
  end
  let(:video_extractor) { double('video extractor') }

  after { file.unlink }

  it 'stores searchable transcript and standard media metadata' do
    processor = described_class.new(document_processor: document_processor, metadata_extractor: metadata_extractor)
    result = processor.create(file.path, title: 'Weekly meeting', tags: ['roadmap'],
                                         audio_transcriber: ->(_path) { 'Discuss the Q3 roadmap' })

    expect(result).to include(document_id: 7, media_type: 'audio', status: 'success', section_count: 1)
    expect(result.dig(:metadata, :semantic, :transcript)).to include('Q3 roadmap')
    expect(document_processor).to have_received(:save_sections) do |_document, chunks, _options|
      expect(chunks.first[:content]).to include('Q3 roadmap')
      expect(chunks.first[:metadata]).to include(media_type: 'audio', extraction_kind: 'audio_transcript')
    end
  end

  it 'stores timestamped audio segments with speaker metadata' do
    processor = described_class.new(document_processor: document_processor, metadata_extractor: metadata_extractor)
    result = processor.create(
      file.path,
      audio_transcriber: lambda do |_path|
        { segments: [{ text: 'Decision approved', start: 1.5, end: 3.2, speaker: 'Alice' }] }
      end
    )

    expect(result.dig(:metadata, :semantic, :transcript)).to eq('Decision approved')
    expect(document_processor).to have_received(:save_sections) do |_document, chunks, _options|
      expect(chunks.first[:metadata]).to include(
        media_type: 'audio', extraction_kind: 'audio_transcript', start_ms: 1500,
        end_ms: 3200, speaker: 'Alice'
      )
    end
  end

  it 'degrades to filename and tags when transcription is unavailable' do
    processor = described_class.new(document_processor: document_processor, metadata_extractor: metadata_extractor)
    result = processor.create(file.path, tags: ['meeting'])

    expect(result[:status]).to eq('partial')
    expect(result[:warnings].join).to include('no audio transcriber')
  end

  it 'creates timestamped video sections from transcript and frame entries' do
    allow(metadata_extractor).to receive(:extract).and_return(
      media_type: 'video',
      media: SmartRAG::Core::MediaMetadataExtractor::DEFAULT_MEDIA.merge(duration_ms: 90_000),
      warnings: []
    )
    allow(video_extractor).to receive(:extract).and_return(
      timeline: [
        { extraction_kind: 'transcript', text: 'Open settings', start_ms: 5000, end_ms: 9000 },
        { extraction_kind: 'frame_description', text: 'Settings screen', frame_timestamp_ms: 30_000,
          start_ms: 30_000, end_ms: 30_000 }
      ],
      warnings: []
    )
    processor = described_class.new(
      document_processor: document_processor,
      metadata_extractor: metadata_extractor,
      video_extractor: video_extractor
    )

    result = processor.create(file.path, media_type: 'video', video_transcriber: ->(_) { 'unused' })

    expect(result).to include(media_type: 'video', status: 'success', section_count: 1)
    expect(document_processor).not_to have_received(:chunk_content)
    expect(document_processor).to have_received(:save_sections) do |_document, chunks, _options|
      expect(chunks.length).to eq(2)
      expect(chunks.first[:title]).to eq('Video transcript 00:00:05')
      expect(chunks.first[:metadata]).to include(
        media_type: 'video', extraction_kind: 'transcript', start_ms: 5000, end_ms: 9000
      )
      expect(chunks.last[:metadata][:frame_timestamp_ms]).to eq(30_000)
    end
  end

  it 'registers stored content before later extraction failure so GC can discover it' do
    store = double('store', put: { content_hash: 'd' * 64, storage_uri: 's3://media/orphan' })
    registry = double('registry')
    allow(registry).to receive(:register)
    allow(registry).to receive(:attach)
    policy = double('policy')
    allow(policy).to receive(:validate_file!).and_return(true)
    calls = 0
    allow(policy).to receive(:with_timeout) do |&block|
      calls += 1
      raise 'semantic extraction crashed' if calls == 2
      block.call
    end
    processor = described_class.new(
      document_processor: document_processor, metadata_extractor: metadata_extractor,
      content_store: store, object_registry: registry, safety_policy: policy
    )

    expect { processor.create(file.path) }.to raise_error('semantic extraction crashed')
    expect(registry).to have_received(:register).with(
      hash_including(storage_uri: 's3://media/orphan'), byte_size: File.size(file.path)
    )
    expect(registry).not_to have_received(:attach)
  end
end
