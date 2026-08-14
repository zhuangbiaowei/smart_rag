# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'transcript_normalizer'

module SmartRAG
  module Core
    class VideoSemanticExtractor
      DEFAULT_FRAME_INTERVAL_SECONDS = 30
      DEFAULT_MAX_FRAMES = 12

      def extract(file_path, duration_ms:, options: {})
        warnings = []
        timeline = []

        Dir.mktmpdir('smart_rag_video') do |directory|
          timeline.concat(transcript_entries(file_path, directory, options, warnings))
          timeline.concat(frame_entries(file_path, directory, duration_ms, options, warnings))
        end

        { timeline: timeline.sort_by { |entry| entry[:start_ms] || entry[:frame_timestamp_ms] || 0 },
          warnings: warnings }
      rescue StandardError => e
        { timeline: [], warnings: ["video semantic extraction failed: #{e.message}"] }
      end

      private

      def transcript_entries(file_path, directory, options, warnings)
        return [] if options[:transcribe] == false

        transcriber = options[:video_transcriber] || options[:audio_transcriber]
        unless transcriber
          warnings << 'no video transcriber configured; video audio transcription skipped'
          return []
        end

        audio_path = File.join(directory, 'audio.wav')
        output, status = Open3.capture2e(
          'ffmpeg', '-y', '-v', 'error', '-i', file_path, '-vn', '-ac', '1', '-ar', '16k', audio_path
        )
        unless status.success? && File.file?(audio_path)
          warnings << "video audio extraction failed: #{output.strip}"
          return []
        end

        TranscriptNormalizer.entries(invoke(transcriber, audio_path))
      rescue Errno::ENOENT
        warnings << 'ffmpeg not available; video audio transcription skipped'
        []
      rescue StandardError => e
        warnings << "video transcription failed: #{e.message}"
        []
      end

      def frame_entries(file_path, directory, duration_ms, options, warnings)
        return [] if options[:llm_caption] == false

        describer = options[:frame_describer] || options[:image_describer]
        unless describer
          warnings << 'no frame describer configured; video frame descriptions skipped'
          return []
        end

        frame_timestamps(file_path, duration_ms, options).filter_map.with_index do |timestamp_ms, index|
          frame_path = File.join(directory, format('frame-%03d.jpg', index))
          output, status = Open3.capture2e(
            'ffmpeg', '-y', '-v', 'error', '-ss', format('%.3f', timestamp_ms / 1000.0),
            '-i', file_path, '-frames:v', '1', '-q:v', '2', frame_path
          )
          unless status.success? && File.file?(frame_path)
            warnings << "video frame extraction failed at #{timestamp_ms}ms: #{output.strip}"
            next
          end

          description = invoke(describer, frame_path, timestamp_ms)
          next if description.to_s.strip.empty?

          { extraction_kind: 'frame_description', text: description.to_s.strip,
            frame_timestamp_ms: timestamp_ms, start_ms: timestamp_ms, end_ms: timestamp_ms }
        rescue Errno::ENOENT
          warnings << 'ffmpeg not available; video frame descriptions skipped'
          break []
        rescue StandardError => e
          warnings << "video frame description failed at #{timestamp_ms}ms: #{e.message}"
          nil
        end
      end

      def frame_timestamps(file_path, duration_ms, options)
        if options.fetch(:scene_detection, true)
          scene_timestamps = detect_scenes(file_path, options)
          return scene_timestamps unless scene_timestamps.empty?
        end

        interval_ms = [options.fetch(:frame_interval_seconds, DEFAULT_FRAME_INTERVAL_SECONDS).to_f * 1000, 1000].max.round
        max_frames = [[options.fetch(:max_frames, DEFAULT_MAX_FRAMES).to_i, 1].max, 100].min
        duration = duration_ms.to_i
        return [0] if duration <= 0

        timestamps = (0...duration).step(interval_ms).first(max_frames)
        timestamps.empty? ? [0] : timestamps
      end

      def detect_scenes(file_path, options)
        return [] if file_path.to_s.empty?

        threshold = options.fetch(:scene_threshold, 0.35).to_f
        max_frames = [[options.fetch(:max_frames, DEFAULT_MAX_FRAMES).to_i, 1].max, 100].min
        output, status = Open3.capture2e(
          'ffmpeg', '-hide_banner', '-i', file_path, '-filter:v', "select='gt(scene,#{threshold})',showinfo",
          '-an', '-f', 'null', '-'
        )
        return [] unless status.success?

        output.scan(/pts_time:([0-9.]+)/).flatten.map { |seconds| (seconds.to_f * 1000).round }.uniq.first(max_frames)
      rescue Errno::ENOENT, SystemCallError
        []
      end

      def invoke(extractor, path, timestamp_ms = nil)
        callable = extractor.respond_to?(:call) ? extractor : extractor.method(:extract)
        timestamp_ms.nil? || callable.arity == 1 ? callable.call(path) : callable.call(path, timestamp_ms)
      end

    end
  end
end
