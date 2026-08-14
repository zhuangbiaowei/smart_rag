# frozen_string_literal: true

module SmartRAG
  module Core
    module TranscriptNormalizer
      module_function

      def entries(result, extraction_kind: 'transcript')
        segments = if result.is_a?(Hash)
                     result[:segments] || result['segments']
                   elsif result.is_a?(Array)
                     result
                   end
        return Array(segments).filter_map { |segment| normalize_segment(segment, extraction_kind) } if segments

        text = result.is_a?(Hash) ? (result[:text] || result['text']) : result
        text.to_s.strip.empty? ? [] : [{ extraction_kind: extraction_kind, text: text.to_s.strip }]
      end

      def normalize_segment(segment, extraction_kind)
        return { extraction_kind: extraction_kind, text: segment.to_s.strip } unless segment.is_a?(Hash)

        text = segment[:text] || segment['text']
        return nil if text.to_s.strip.empty?

        {
          extraction_kind: extraction_kind,
          text: text.to_s.strip,
          start_ms: timestamp_ms(segment, :start),
          end_ms: timestamp_ms(segment, :end),
          speaker: segment[:speaker] || segment['speaker']
        }.compact
      end

      def timestamp_ms(segment, key)
        explicit = segment["#{key}_ms".to_sym] || segment["#{key}_ms"]
        return explicit.to_f.round unless explicit.nil?

        seconds = segment[key] || segment[key.to_s]
        seconds.nil? ? nil : (seconds.to_f * 1000).round
      end
    end
  end
end
