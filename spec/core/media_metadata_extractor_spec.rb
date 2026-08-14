# frozen_string_literal: true

require 'unit_spec_helper'
require 'tmpdir'
require 'smart_rag/core/media_metadata_extractor'

RSpec.describe SmartRAG::Core::MediaMetadataExtractor do
  subject(:extractor) { described_class.new }

  it 'detects image, audio, video and document extensions' do
    expect(extractor.detect_media_type('photo.JPG')).to eq('image')
    expect(extractor.detect_media_type('meeting.wav')).to eq('audio')
    expect(extractor.detect_media_type('demo.mp4')).to eq('video')
    expect(extractor.detect_media_type('notes.md')).to eq('document')
  end

  it 'rejects unsupported explicit media types' do
    expect { extractor.extract('anything.bin', media_type: 'archive') }
      .to raise_error(ArgumentError, /unsupported media_type/)
  end

  it 'returns a wide metadata schema when an optional dependency is unavailable' do
    allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)
    result = extractor.extract('/tmp/missing.wav', media_type: 'audio')

    expect(result[:media_type]).to eq('audio')
    expect(result[:media]).to include(duration_ms: nil, sample_rate_hz: nil, codec: nil)
    expect(result[:warnings]).not_to be_empty
  end
end
