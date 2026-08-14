# frozen_string_literal: true

require 'unit_spec_helper'
require 'tmpdir'
require 'smart_rag/core/video_semantic_extractor'

RSpec.describe SmartRAG::Core::VideoSemanticExtractor do
  subject(:extractor) { described_class.new }

  it 'normalizes timestamped transcript segments and describes sampled frames' do
    capture_index = 0
    allow(Open3).to receive(:capture2e) do |*args|
      output_path = args.last
      File.write(output_path, 'generated')
      capture_index += 1
      ['', instance_double(Process::Status, success?: true)]
    end
    transcriber = lambda do |_audio_path|
      { segments: [{ text: 'Intro', start: 1.5, end: 3.0 }] }
    end
    describer = ->(_frame_path, timestamp_ms) { "Frame at #{timestamp_ms}" }

    result = extractor.extract(
      '/tmp/video.mp4', duration_ms: 65_000,
      options: { video_transcriber: transcriber, frame_describer: describer,
                 frame_interval_seconds: 30, max_frames: 2, scene_detection: false }
    )

    expect(capture_index).to eq(3)
    expect(result[:warnings]).to be_empty
    expect(result[:timeline]).to include(
      hash_including(extraction_kind: 'transcript', text: 'Intro', start_ms: 1500, end_ms: 3000),
      hash_including(extraction_kind: 'frame_description', frame_timestamp_ms: 0),
      hash_including(extraction_kind: 'frame_description', frame_timestamp_ms: 30_000)
    )
  end

  it 'degrades when ffmpeg is unavailable' do
    allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)

    result = extractor.extract(
      '/tmp/video.mp4', duration_ms: 1000,
      options: { video_transcriber: ->(_) { 'text' }, frame_describer: ->(_) { 'frame' } }
    )

    expect(result[:timeline]).to be_empty
    expect(result[:warnings].join).to include('ffmpeg not available')
  end

  it 'does not rescale explicit millisecond timestamps' do
    allow(Open3).to receive(:capture2e) do |*args|
      File.write(args.last, 'audio')
      ['', instance_double(Process::Status, success?: true)]
    end

    result = extractor.extract(
      '/tmp/video.mp4', duration_ms: 10_000,
      options: { video_transcriber: ->(_) { [{ text: 'Short', start_ms: 5000, end_ms: 9000 }] },
                 llm_caption: false }
    )

    expect(result[:timeline].first).to include(start_ms: 5000, end_ms: 9000)
  end

  it 'warns for an unconfigured semantic channel unless it is explicitly disabled' do
    allow(Open3).to receive(:capture2e) do |*args|
      File.write(args.last, 'audio')
      ['', instance_double(Process::Status, success?: true)]
    end

    partial = extractor.extract(
      '/tmp/video.mp4', duration_ms: 1000,
      options: { video_transcriber: ->(_) { 'Transcript' } }
    )
    complete = extractor.extract(
      '/tmp/video.mp4', duration_ms: 1000,
      options: { video_transcriber: ->(_) { 'Transcript' }, llm_caption: false }
    )

    expect(partial[:warnings].join).to include('no frame describer')
    expect(complete[:warnings]).to be_empty
  end

  it 'accepts an array of transcript strings' do
    allow(Open3).to receive(:capture2e) do |*args|
      File.write(args.last, 'audio')
      ['', instance_double(Process::Status, success?: true)]
    end

    result = extractor.extract(
      '/tmp/video.mp4', duration_ms: 1000,
      options: { video_transcriber: ->(_) { ['First sentence', 'Second sentence'] },
                 llm_caption: false }
    )

    expect(result[:timeline].map { |entry| entry[:text] }).to eq(['First sentence', 'Second sentence'])
  end
end
