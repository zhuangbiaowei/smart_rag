# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'open3'
require 'timeout'
require 'uri'

module SmartRAG
  module Core
    module MediaExtractors
      class OpenAICompatible
        def initialize(base_url:, api_key:, vision_model: nil, transcription_model: nil,
                       timeout_seconds: 120, language: nil)
          @base_url = base_url.to_s.sub(%r{/+$}, '')
          @api_key = api_key
          @vision_model = vision_model
          @transcription_model = transcription_model
          @timeout_seconds = timeout_seconds.to_i
          @language = language
        end

        def describe(file_path, _timestamp_ms = nil)
          raise ArgumentError, 'vision_model is not configured' if @vision_model.to_s.empty?

          mime = mime_type(file_path)
          body = {
            model: @vision_model,
            messages: [{ role: 'user', content: [
              { type: 'text', text: 'Describe this image precisely for retrieval. Include visible text and important objects.' },
              { type: 'image_url', image_url: { url: "data:#{mime};base64,#{Base64.strict_encode64(File.binread(file_path))}" } }
            ] }],
            temperature: 0.1
          }
          parsed = post_json('/v1/chat/completions', body)
          parsed.dig('choices', 0, 'message', 'content').to_s.strip
        end

        alias extract describe

        def transcribe(file_path)
          raise ArgumentError, 'transcription_model is not configured' if @transcription_model.to_s.empty?

          boundary = "SmartRAG#{rand(1_000_000_000)}"
          fields = { 'model' => @transcription_model, 'response_format' => 'verbose_json',
                     'timestamp_granularities[]' => 'segment' }
          fields['language'] = @language unless @language.to_s.empty?
          body = multipart_body(boundary, fields, file_path)
          response = request('/v1/audio/transcriptions', body, "multipart/form-data; boundary=#{boundary}")
          JSON.parse(response.body)
        end

        private

        def post_json(path, body)
          response = request(path, JSON.generate(body), 'application/json')
          JSON.parse(response.body)
        end

        def request(path, body, content_type)
          uri = URI.parse("#{@base_url}#{path}")
          request = Net::HTTP::Post.new(uri)
          request['Authorization'] = "Bearer #{@api_key}" unless @api_key.to_s.empty?
          request['Content-Type'] = content_type
          request.body = body
          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                     open_timeout: @timeout_seconds, read_timeout: @timeout_seconds) do |http|
            http.request(request)
          end
          raise "media model HTTP #{response.code}: #{response.body.to_s[0, 300]}" unless response.is_a?(Net::HTTPSuccess)
          response
        end

        def multipart_body(boundary, fields, file_path)
          body = +''
          fields.each do |key, value|
            body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
          end
          body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(file_path)}\"\r\n"
          body << "Content-Type: #{mime_type(file_path)}\r\n\r\n"
          body << File.binread(file_path)
          body << "\r\n--#{boundary}--\r\n"
          body
        end

        def mime_type(path)
          { '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png',
            '.webp' => 'image/webp', '.wav' => 'audio/wav', '.mp3' => 'audio/mpeg',
            '.m4a' => 'audio/mp4' }.fetch(File.extname(path).downcase, 'application/octet-stream')
        end
      end

      class Tesseract
        def initialize(language: nil, timeout_seconds: 60)
          @language = language
          @timeout_seconds = timeout_seconds.to_i
        end

        def available?
          system('which', 'tesseract', out: File::NULL, err: File::NULL)
        end

        def extract(file_path)
          raise 'tesseract is not installed' unless available?

          args = ['tesseract', file_path, 'stdout']
          args.concat(['-l', @language]) unless @language.to_s.empty?
          output = nil
          status = nil
          Timeout.timeout(@timeout_seconds) { output, status = Open3.capture2e(*args) }
          raise "tesseract failed: #{output.to_s.strip}" unless status.success?

          output.to_s.strip
        end
      end

      module Factory
        module_function

        def build(config)
          media = config || {}
          extractors = {}
          if media[:openai]
            adapter = OpenAICompatible.new(**media[:openai])
            extractors[:image_describer] = adapter.method(:describe) if media.dig(:openai, :vision_model)
            if media.dig(:openai, :transcription_model)
              extractors[:audio_transcriber] = adapter.method(:transcribe)
              extractors[:video_transcriber] = adapter.method(:transcribe)
            end
          end
          if media[:ocr]&.fetch(:provider, nil).to_s == 'tesseract'
            extractors[:ocr_extractor] = Tesseract.new(**media[:ocr].reject { |key, _| key == :provider })
          end
          extractors
        end
      end
    end
  end
end
