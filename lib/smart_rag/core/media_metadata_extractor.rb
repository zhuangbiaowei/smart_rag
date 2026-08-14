# frozen_string_literal: true

require 'json'
require 'open3'

module SmartRAG
  module Core
    class MediaMetadataExtractor
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .bmp .tif .tiff .heic .heif].freeze
      AUDIO_EXTENSIONS = %w[.mp3 .wav .m4a .aac .flac .ogg .oga .opus .wma .aif .aiff].freeze
      VIDEO_EXTENSIONS = %w[.mp4 .mkv .mov .webm .avi .flv .wmv .m4v .ts .mpeg .mpg].freeze
      DOCUMENT_EXTENSIONS = %w[.pdf .doc .docx .xls .xlsx .ppt .pptx .md .markdown .txt .text .html .htm .csv .json].freeze
      MEDIA_TYPES = %w[image audio video document other].freeze
      DEFAULT_MEDIA = {
        format: nil, width: nil, height: nil, dpi: nil, color_mode: nil,
        orientation: nil, exif: {}, duration_ms: nil, bitrate_bps: nil,
        sample_rate_hz: nil, channels: nil, codec: nil, fps: nil,
        audio_codec: nil, frame_count: nil
      }.freeze

      def extract(file_path, media_type: nil)
        type = normalize_media_type(media_type || detect_media_type(file_path))
        media = DEFAULT_MEDIA.dup
        warnings = []

        case type
        when 'image' then extract_image(file_path, media, warnings)
        when 'audio' then extract_audio(file_path, media, warnings)
        when 'video' then extract_video(file_path, media, warnings)
        end

        { media_type: type, media: media, warnings: warnings }
      rescue ArgumentError
        raise
      rescue StandardError => e
        { media_type: type || 'other', media: media || DEFAULT_MEDIA.dup,
          warnings: ["media metadata extraction failed: #{e.message}"] }
      end

      def detect_media_type(file_path)
        extension = File.extname(file_path.to_s).downcase
        return 'image' if IMAGE_EXTENSIONS.include?(extension)
        return 'audio' if AUDIO_EXTENSIONS.include?(extension)
        return 'video' if VIDEO_EXTENSIONS.include?(extension)
        return 'document' if DOCUMENT_EXTENSIONS.include?(extension)

        detect_from_mime(file_path)
      end

      private

      def normalize_media_type(value)
        type = value.to_s
        type = 'other' if type.empty? || type == 'auto'
        raise ArgumentError, "unsupported media_type: #{value}" unless MEDIA_TYPES.include?(type)

        type
      end

      def detect_from_mime(file_path)
        return 'other' unless File.file?(file_path)

        output, status = Open3.capture2e('file', '--brief', '--mime-type', file_path)
        return 'other' unless status.success?

        mime = output.strip
        return 'image' if mime.start_with?('image/')
        return 'audio' if mime.start_with?('audio/')
        return 'video' if mime.start_with?('video/')
        return 'document' if mime.start_with?('text/', 'application/pdf')

        'other'
      rescue Errno::ENOENT, SystemCallError
        'other'
      end

      def extract_image(file_path, media, warnings)
        python = %w[python3 python].find do |command|
          system(command, '-c', 'import PIL', out: File::NULL, err: File::NULL)
        end
        unless python
          warnings << 'Pillow (PIL) not available; image metadata skipped'
          return
        end

        script = <<~PYTHON
          import json, sys
          from PIL import Image, ExifTags, ImageOps
          image = Image.open(sys.argv[1])
          frame_count = getattr(image, 'n_frames', 1)
          image = ImageOps.exif_transpose(image)
          info = {'format': (image.format or '').lower() or None,
                  'width': image.width, 'height': image.height,
                  'color_mode': image.mode, 'frame_count': frame_count, 'exif': {}}
          dpi = image.info.get('dpi')
          if dpi and isinstance(dpi[0], (int, float)):
              info['dpi'] = round(dpi[0])
          try:
              raw = image.getexif()
              allowed = {'DateTime', 'DateTimeOriginal', 'Make', 'Model', 'Orientation'}
              for key, value in raw.items():
                  name = ExifTags.TAGS.get(key, str(key))
                  if name in allowed and isinstance(value, (int, float, str)):
                      info['exif'][name] = value
          except Exception:
              pass
          print(json.dumps(info))
        PYTHON
        output, status = Open3.capture2e(python, '-c', script, file_path)
        unless status.success?
          warnings << "image metadata extraction failed: #{output.strip}"
          return
        end

        parsed = JSON.parse(output)
        %w[format width height dpi color_mode frame_count exif].each { |key| media[key.to_sym] = parsed[key] if parsed.key?(key) }
        media[:orientation] = orientation(media[:width], media[:height])
      end

      def extract_audio(file_path, media, warnings)
        probe = ffprobe(file_path, warnings)
        return unless probe

        format = probe['format'] || {}
        stream = Array(probe['streams']).find { |item| item['codec_type'] == 'audio' }
        media[:format] = File.extname(file_path).downcase.delete_prefix('.')
        media[:duration_ms] = milliseconds(format['duration'])
        media[:bitrate_bps] = integer(format['bit_rate']) || integer(stream && stream['bit_rate'])
        media[:sample_rate_hz] = integer(stream && stream['sample_rate'])
        media[:channels] = integer(stream && stream['channels'])
        media[:codec] = stream && stream['codec_name']
      end

      def extract_video(file_path, media, warnings)
        probe = ffprobe(file_path, warnings)
        return unless probe

        format = probe['format'] || {}
        streams = Array(probe['streams'])
        video = streams.find { |item| item['codec_type'] == 'video' }
        audio = streams.find { |item| item['codec_type'] == 'audio' }
        media[:format] = File.extname(file_path).downcase.delete_prefix('.')
        media[:duration_ms] = milliseconds(format['duration'])
        media[:bitrate_bps] = integer(format['bit_rate'])
        media[:width] = integer(video && video['width'])
        media[:height] = integer(video && video['height'])
        media[:codec] = video && video['codec_name']
        media[:fps] = frame_rate(video)
        media[:audio_codec] = audio && audio['codec_name']
        media[:orientation] = orientation(media[:width], media[:height])
      end

      def ffprobe(file_path, warnings)
        output, status = Open3.capture2e('ffprobe', '-v', 'quiet', '-print_format', 'json',
                                         '-show_format', '-show_streams', file_path)
        unless status.success?
          warnings << "ffprobe failed: #{output.strip}"
          return nil
        end
        JSON.parse(output)
      rescue Errno::ENOENT
        warnings << 'ffprobe not available; audio/video metadata skipped'
        nil
      rescue JSON::ParserError, SystemCallError => e
        warnings << "ffprobe failed: #{e.message}"
        nil
      end

      def milliseconds(value) = value.nil? ? nil : (value.to_f * 1000).round
      def integer(value) = value.nil? ? nil : Integer(value.to_s, exception: false)

      def frame_rate(stream)
        return nil unless stream
        numerator, denominator = stream['avg_frame_rate'].to_s.split('/')
        return nil if numerator.to_s.empty? || denominator.to_i.zero?

        (numerator.to_f / denominator.to_f).round(2)
      end

      def orientation(width, height)
        return nil unless width && height
        return 'square' if width == height

        width > height ? 'landscape' : 'portrait'
      end
    end
  end
end
