# frozen_string_literal: true

require 'json'
require 'rack'
require 'fileutils'
require 'tmpdir'
require 'securerandom'
require_relative 'http_access_policy'
require_relative 'core/media_job_queue'

module SmartRAG
  class HttpApp
    OPERATIONS = %w[add_document add_media add_image add_audio add_video].freeze

    def initialize(rag:, extractors: {}, access_policy: nil)
      @rag = rag
      @extractors = symbolize_keys(extractors)
      @access_policy = access_policy
    end

    def call(env)
      request = Rack::Request.new(env)
      return health if request.get? && request.path == '/healthz'
      principal = authorize(request)
      request.env['smart_rag.principal'] = principal
      return retrieve(request) if request.post? && request.path == '/v1/retrieve'
      return ingest(request) if request.post? && request.path == '/v1/media'
      return list_media_jobs(request) if request.get? && request.path == '/v1/media/jobs'
      if request.get? && request.path == '/v1/media/jobs/stats'
        return json(200, access_policy ? rag.media_job_statistics(principal: principal) : rag.media_job_statistics)
      end
      if request.post? && (match = request.path.match(%r{\A/v1/media/jobs/(\d+)/(cancel|retry)\z}))
        return mutate_media_job(match[1], match[2], principal)
      end
      if request.get? && request.path.match?(%r{\A/v1/media/jobs/\d+\z})
        job_id = request.path.split('/').last
        job = access_policy ? rag.media_job(job_id, principal: principal) : rag.media_job(job_id)
        return job ? json(200, job) : json(404, error: 'media job not found')
      end

      json(404, error: 'not found')
    rescue JSON::ParserError => e
      json(400, error: "invalid JSON: #{e.message}")
    rescue ArgumentError => e
      json(400, error: e.message)
    rescue HttpAccessPolicy::Unauthorized => e
      json(401, error: e.message)
    rescue HttpAccessPolicy::QuotaExceeded => e
      json(429, error: e.message)
    rescue Core::MediaJobQueue::IdempotencyConflict => e
      json(409, error: e.message, code: 'idempotency_conflict')
    rescue StandardError => e
      json(500, error: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :rag, :extractors, :access_policy

    def authorize(request)
      return 'anonymous' unless access_policy
      principal = access_policy.authorize!(request)
      bytes = request.post? && request.path == '/v1/media' ? request.content_length.to_i : 0
      access_policy.consume!(principal, request_bytes: bytes)
      principal
    end

    def health
      payload = { status: 'ok' }
      payload[:media_jobs] = rag.media_job_statistics if rag.respond_to?(:media_job_statistics)
      json(200, payload)
    rescue StandardError => e
      json(503, status: 'degraded', error: "media job queue unavailable: #{e.message}")
    end

    def list_media_jobs(request)
      options = { status: request.params['status'], limit: request.params.fetch('limit', 20),
                  offset: request.params.fetch('offset', 0) }
      options[:principal] = request.env['smart_rag.principal'] if access_policy
      json(200, rag.media_jobs(**options))
    end

    def mutate_media_job(job_id, action, principal)
      result = if action == 'cancel'
                 access_policy ? rag.cancel_media_job(job_id, principal: principal) : rag.cancel_media_job(job_id)
               else
                 access_policy ? rag.retry_media_job(job_id, principal: principal) : rag.retry_media_job(job_id)
               end
      return json(404, error: 'media job not found') unless result
      return json(409, result) if result[:transition_error]

      json(200, result)
    end

    def retrieve(request)
      body = json_body(request)
      plan = symbolize_keys(body.fetch('plan', body))
      plan[:_principal] = request.env['smart_rag.principal'] if access_policy
      json(200, rag.retrieve(plan: plan))
    end

    def ingest(request)
      payload, source, cleanup_path = if request.media_type.to_s.start_with?('multipart/form-data')
                                        multipart_payload(request)
                                      else
                                        json_payload(request)
                                      end
      operation = payload.fetch(:operation).to_s
      raise ArgumentError, "unsupported operation: #{operation}" unless OPERATIONS.include?(operation)
      raise ArgumentError, 'source is required' if source.to_s.empty?

      options = symbolize_keys(payload[:options] || {}).merge(extractors)
      options[:principal] = request.env['smart_rag.principal'] if access_policy
      if options.delete(:async)
        source, cleanup_path = persist_async_upload(source, cleanup_path)
        staged = rag.stage_media_upload(source) if File.file?(source) && rag.respond_to?(:stage_media_upload)
        if staged
          File.delete(source) if File.file?(source)
          source = staged[:storage_uri]
          options[:staging_media_object_id] = staged[:media_object_id]
        else
          options[:delete_source_after] = true if File.file?(source)
        end
        options[:idempotency_key] ||= request.get_header('HTTP_IDEMPOTENCY_KEY')
        return json(202, rag.enqueue_media(source, options.merge(operation: operation.to_sym)))
      end
      json(200, rag.public_send(operation, source, options))
    ensure
      File.delete(cleanup_path) if cleanup_path && File.exist?(cleanup_path)
    end

    def json_payload(request)
      payload = symbolize_keys(json_body(request))
      [payload, payload[:source], nil]
    end

    def multipart_payload(request)
      params = request.params
      upload = params['file']
      tempfile = upload.is_a?(Hash) && (upload[:tempfile] || upload['tempfile'])
      filename = upload.is_a?(Hash) && (upload[:filename] || upload['filename'])
      raise ArgumentError, 'multipart file is required' unless tempfile

      extension = File.extname(filename.to_s)
      source = tempfile.path
      unless extension.empty? || File.extname(source).downcase == extension.downcase
        preserved = File.join(Dir.tmpdir, "smart-rag-upload-#{Process.pid}-#{object_id}#{extension}")
        FileUtils.cp(source, preserved)
        source = preserved
      end

      payload = {
        operation: params['operation'],
        options: params['options'].to_s.empty? ? {} : JSON.parse(params['options'])
      }
      [symbolize_keys(payload), source, source == tempfile.path ? nil : source]
    end

    def json_body(request)
      content = request.body.read
      content.empty? ? {} : JSON.parse(content)
    end

    def persist_async_upload(source, cleanup_path)
      return [source, cleanup_path] unless File.file?(source)

      directory = ENV.fetch('SMARTRAG_MEDIA_JOB_UPLOAD_DIR', File.join(Dir.tmpdir, 'smart-rag-media-jobs'))
      FileUtils.mkdir_p(directory)
      extension = File.extname(source)
      destination = File.join(directory, "#{SecureRandom.uuid}#{extension}")
      FileUtils.cp(source, destination)
      [destination, cleanup_path]
    end

    def symbolize_keys(value)
      return value.map { |item| symbolize_keys(item) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, item), result|
        result[key.to_sym] = symbolize_keys(item)
      end
    end

    def json(status, payload)
      [status, { 'content-type' => 'application/json' }, [JSON.generate(payload)]]
    end
  end
end
