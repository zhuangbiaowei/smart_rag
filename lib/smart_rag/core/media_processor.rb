# frozen_string_literal: true

require 'digest'
require_relative 'media_metadata_extractor'
require_relative 'video_semantic_extractor'
require_relative 'transcript_normalizer'
require_relative 'media_safety_policy'

module SmartRAG
  module Core
    class MediaProcessor
      CONTENT_SUMMARY_LIMIT = 4000

      def initialize(document_processor:, metadata_extractor: MediaMetadataExtractor.new,
                     video_extractor: VideoSemanticExtractor.new, safety_policy: MediaSafetyPolicy.new,
                     content_store: nil, object_registry: nil, default_extractors: {}, logger: nil)
        @document_processor = document_processor
        @metadata_extractor = metadata_extractor
        @video_extractor = video_extractor
        @safety_policy = safety_policy
        @content_store = content_store
        @object_registry = object_registry
        @default_extractors = default_extractors
        @logger = logger || Logger.new($stdout)
      end

      def create(source, options = {})
        options = default_extractors.merge(options)
        file_path, materialized_file = resolve_source(source, options)
        safety_policy.validate_file!(file_path)
        requested_type = options[:media_type]
        requested_type = nil if requested_type.to_s == 'auto'
        extracted = safety_policy.with_timeout do
          metadata_extractor.extract(file_path, media_type: requested_type)
        end
        safety_policy.validate_file!(file_path, duration_ms: extracted.dig(:media, :duration_ms))
        stored = content_store&.put(file_path)
        object_registry&.register(stored, byte_size: File.size(file_path)) if stored
        semantic, timeline, warnings = safety_policy.with_timeout do
          extract_semantic(file_path, extracted[:media_type], extracted[:media], options)
        end
        searchable_text = searchable_text_for(source, semantic, options)
        metadata = build_metadata(file_path, extracted, semantic, searchable_text, options, stored)

        chunks = timeline.empty? ? document_processor.chunk_content(searchable_text, options) : timeline_chunks(timeline)
        document, sections = persist(source, metadata, chunks, options, stored)

        all_warnings = Array(extracted[:warnings]) + warnings
        {
          document_id: document.id,
          media_type: extracted[:media_type],
          status: all_warnings.empty? ? 'success' : 'partial',
          section_count: sections.length,
          metadata: metadata.reject { |key, _| key == :content },
          warnings: all_warnings
        }
      ensure
        document_processor.cleanup_downloaded_file if document_processor.respond_to?(:cleanup_downloaded_file)
        File.delete(materialized_file) if materialized_file && File.file?(materialized_file)
      end

      private

      attr_reader :document_processor, :metadata_extractor, :video_extractor, :safety_policy,
                  :content_store, :default_extractors, :logger

      def resolve_source(source, options)
        if source.to_s.match?(%r{\A(?:file|s3)://})
          raise ArgumentError, 'configured content store cannot read media job source' unless content_store
          path, temporary = content_store.materialize(source)
          return [path, temporary ? path : nil]
        end
        if source.to_s.match?(%r{\Ahttps?://})
          safety_policy.validate_url!(source)
          return [document_processor.download_from_url(source, options.merge(
            max_file_size: safety_policy.max_bytes, download_timeout: safety_policy.command_timeout
          )), nil]
        end
        return [source, nil] if File.file?(source)

        raise ArgumentError, "Invalid source: #{source}. Must be a valid URL or file path."
      end

      def extract_semantic(file_path, media_type, media, options)
        warnings = []
        captions = []
        timeline = []
        ocr_text = invoke_extractor(options[:ocr_extractor], file_path, warnings, 'image OCR') if media_type == 'image'
        if media_type == 'image'
          caption = invoke_extractor(options[:image_describer], file_path, warnings, 'image description')
          captions << caption unless caption.to_s.strip.empty?
        end
        if media_type == 'audio'
          transcript_result = invoke_extractor(options[:audio_transcriber], file_path, warnings, 'audio transcription')
          timeline = TranscriptNormalizer.entries(transcript_result, extraction_kind: 'audio_transcript')
          transcript = timeline.map { |entry| entry[:text] }.join("\n")
        end
        if media_type == 'video'
          video_result = video_extractor.extract(file_path, duration_ms: media[:duration_ms], options: options)
          timeline = Array(video_result[:timeline])
          warnings.concat(Array(video_result[:warnings]))
          transcript_entries = timeline.select { |entry| entry[:extraction_kind] == 'transcript' }
          frame_entries = timeline.select { |entry| entry[:extraction_kind] == 'frame_description' }
          transcript = transcript_entries.map { |entry| entry[:text] }.join("\n")
          captions.concat(frame_entries.map { |entry| entry[:text] })
        end

        description = options[:description]
        if media_type == 'image' && description.to_s.empty? && captions.empty? && ocr_text.to_s.empty?
          warnings << 'no image semantic extractor configured; indexed filename and tags only'
        elsif media_type == 'audio' && transcript.to_s.empty?
          warnings << 'no audio transcriber configured; indexed filename and tags only'
        elsif media_type == 'video' && timeline.empty? &&
              (options[:transcribe] != false || options[:llm_caption] != false)
          warnings << 'no video transcriber or frame describer configured; indexed filename and tags only'
        end

        [{ description: description, captions: captions, transcript: transcript,
           ocr_text: ocr_text, tags: Array(options[:tags]).map(&:to_s) }, timeline, warnings]
      end

      def invoke_extractor(extractor, file_path, warnings, label)
        return nil unless extractor

        extractor.respond_to?(:call) ? extractor.call(file_path) : extractor.extract(file_path)
      rescue StandardError => e
        warnings << "#{label} failed: #{e.message}"
        nil
      end

      def searchable_text_for(source, semantic, options)
        parts = [options[:title] || File.basename(source.to_s), semantic[:description],
                 semantic[:captions], semantic[:ocr_text], semantic[:transcript], semantic[:tags]].flatten
        parts.map(&:to_s).map(&:strip).reject(&:empty?).uniq.join("\n\n")
      end

      def build_metadata(file_path, extracted, semantic, searchable_text, options, stored)
        user_metadata = symbolize_keys(options[:metadata] || {})
        user_metadata.merge(
          schema_version: 1,
          principal: options[:principal] || 'system',
          file_path: file_path,
          file_size: File.size(file_path),
          file_type: File.extname(file_path).downcase,
          content_hash: Digest::SHA256.file(file_path).hexdigest,
          storage_uri: stored && stored[:storage_uri],
          media_type: extracted[:media_type],
          media: extracted[:media],
          semantic: semantic,
          title: options[:title],
          author: options[:author],
          description: options[:description],
          content: searchable_text[0, CONTENT_SUMMARY_LIMIT]
        ).compact
      end

      def timeline_chunks(timeline)
        timeline.map.with_index do |entry, index|
          timestamp = entry[:start_ms] || entry[:frame_timestamp_ms]
          {
            title: timeline_title(entry[:extraction_kind], timestamp, index),
            content: entry[:text],
            metadata: entry.reject { |key, _| key == :text }.merge(
              media_type: entry[:extraction_kind] == 'audio_transcript' ? 'audio' : 'video'
            )
          }
        end
      end

      def timeline_title(kind, timestamp_ms, index)
        label = case kind
                when 'frame_description' then 'Video frame'
                when 'audio_transcript' then 'Audio transcript'
                else 'Video transcript'
                end
        return "#{label} #{index + 1}" unless timestamp_ms

        total_seconds = timestamp_ms.to_i / 1000
        format('%s %02d:%02d:%02d', label, total_seconds / 3600, (total_seconds / 60) % 60, total_seconds % 60)
      end

      def persist(source, metadata, chunks, options, stored)
        db = persistence_db
        return persist_without_outer_transaction(source, metadata, chunks, options, stored) unless db

        document = nil
        sections = nil
        db.transaction do
          document = document_processor.create_or_update_document(source, metadata, options)
          section_ids = db[:source_sections].where(document_id: document.id).select_map(:id)
          db[:embeddings].where(source_id: section_ids).delete if section_ids.any? && db.table_exists?(:embeddings)
          db[:source_sections].where(document_id: document.id).delete
          sections = document_processor.save_sections(document, chunks, options)
          object_registry&.attach(document.id, stored, byte_size: metadata[:file_size])
          document.set_download_state(:completed)
        end
        [document, sections]
      end

      def persist_without_outer_transaction(source, metadata, chunks, options, stored)
        document = document_processor.create_or_update_document(source, metadata, options)
        db = document.class.db
        sections = nil
        db.transaction do
          section_ids = db[:source_sections].where(document_id: document.id).select_map(:id)
          db[:embeddings].where(source_id: section_ids).delete if section_ids.any? && db.table_exists?(:embeddings)
          db[:source_sections].where(document_id: document.id).delete
          sections = document_processor.save_sections(document, chunks, options)
          object_registry&.attach(document.id, stored, byte_size: metadata[:file_size])
          document.set_download_state(:completed)
        end
        [document, sections]
      end

      def persistence_db
        ::SmartRAG::Models::SourceDocument.db
      rescue StandardError
        nil
      end

      def object_registry = @object_registry

      def symbolize_keys(hash)
        hash.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
      end
    end
  end
end
