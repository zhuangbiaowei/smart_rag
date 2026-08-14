# frozen_string_literal: true

require 'unit_spec_helper'
require 'tmpdir'
require 'tempfile'
require 'smart_rag/core/local_content_store'
require 'smart_rag/core/media_safety_policy'
require 'smart_rag/core/transcript_normalizer'
require 'smart_rag/core/media_extractors'

RSpec.describe 'media P1 components' do
  it 'normalizes verbose transcription segments into milliseconds' do
    entries = SmartRAG::Core::TranscriptNormalizer.entries(
      { 'segments' => [{ 'text' => 'hello', 'start' => 1.25, 'end' => 2.5, 'speaker' => 'A' }] },
      extraction_kind: 'audio_transcript'
    )

    expect(entries).to eq([{ extraction_kind: 'audio_transcript', text: 'hello',
                             start_ms: 1250, end_ms: 2500, speaker: 'A' }])
  end

  it 'deduplicates files in the local content-addressed store' do
    Dir.mktmpdir do |directory|
      file = Tempfile.new(['asset', '.jpg'])
      file.write('same bytes')
      file.close
      store = SmartRAG::Core::LocalContentStore.new(root: directory)

      first = store.put(file.path)
      second = store.put(file.path)
      expect(second).to eq(first)
      expect(File.binread(first[:stored_path])).to eq('same bytes')
      expect(Dir.glob(File.join(directory, '**', '*.jpg')).length).to eq(1)
    ensure
      file&.unlink
    end
  end

  it 'rejects oversized files and private URL targets' do
    file = Tempfile.new('large').tap { |item| item.write('12345'); item.close }
    policy = SmartRAG::Core::MediaSafetyPolicy.new(max_bytes: 4)
    allow(Resolv).to receive(:getaddresses).with('internal.example').and_return(['127.0.0.1'])

    expect { policy.validate_file!(file.path) }.to raise_error(ArgumentError, /exceeds/)
    expect { policy.validate_url!('https://internal.example/a.mp4') }.to raise_error(ArgumentError, /private/)
  ensure
    file&.unlink
  end

  it 'builds configured OCR and OpenAI-compatible adapters' do
    extractors = SmartRAG::Core::MediaExtractors::Factory.build(
      openai: { base_url: 'https://models.example', api_key: 'secret', vision_model: 'vision',
                transcription_model: 'whisper' },
      ocr: { provider: 'tesseract', language: 'eng' }
    )

    expect(extractors.keys).to contain_exactly(:image_describer, :audio_transcriber,
                                                :video_transcriber, :ocr_extractor)
  end
end
