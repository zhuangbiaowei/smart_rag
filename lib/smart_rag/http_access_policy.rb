# frozen_string_literal: true

require 'digest'

module SmartRAG
  class HttpAccessPolicy
    class Unauthorized < StandardError; end
    class QuotaExceeded < StandardError; end

    def initialize(db:, config: {}, clock: -> { Time.now })
      @db = db
      @config = config || {}
      @clock = clock
      @token_digests = configured_tokens.to_h { |principal, token| [digest(token), principal.to_s] }
    end

    def authorize!(request)
      return 'anonymous' unless config.fetch(:enabled, false)

      scheme, token = request.get_header('HTTP_AUTHORIZATION').to_s.split(' ', 2)
      principal = token_digests[digest(token)] if scheme.to_s.casecmp('Bearer').zero? && token
      raise Unauthorized, 'invalid or missing bearer token' unless principal
      principal
    end

    def consume!(principal, request_bytes: 0)
      return unless quota_enabled?
      raise QuotaExceeded, 'quota storage is unavailable' unless db&.table_exists?(:api_rate_limits)

      enforce_window!(principal, 'minute', minute_start, requests: 1,
                       request_limit: config.dig(:quota, :requests_per_minute))
      enforce_window!(principal, 'day', day_start, bytes: request_bytes.to_i,
                       byte_limit: config.dig(:quota, :upload_bytes_per_day))
    end

    private

    attr_reader :db, :config, :clock, :token_digests

    def configured_tokens
      tokens = config[:tokens]
      return tokens if tokens.is_a?(Hash)
      token = config[:token].to_s
      token.empty? ? {} : { config.fetch(:principal, 'default') => token }
    end

    def digest(value)
      Digest::SHA256.hexdigest(value.to_s)
    end

    def quota_enabled?
      quota = config[:quota] || {}
      quota[:requests_per_minute].to_i.positive? || quota[:upload_bytes_per_day].to_i.positive?
    end

    def minute_start
      now = clock.call
      Time.new(now.year, now.month, now.day, now.hour, now.min, 0, now.utc_offset)
    end

    def day_start
      now = clock.call
      Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
    end

    def enforce_window!(principal, period, window_start, requests: 0, bytes: 0,
                        request_limit: nil, byte_limit: nil)
      return if request_limit.to_i <= 0 && byte_limit.to_i <= 0

      db.transaction do
        dataset = db[:api_rate_limits].where(principal: principal, period: period, window_start: window_start)
        row = dataset.for_update.first
        unless row
          db[:api_rate_limits].insert(principal: principal, period: period, window_start: window_start,
                                      request_count: 0, byte_count: 0, updated_at: clock.call)
          row = dataset.for_update.first
        end
        next_requests = row[:request_count].to_i + requests
        next_bytes = row[:byte_count].to_i + bytes
        raise QuotaExceeded, "#{period} request quota exceeded" if request_limit.to_i.positive? && next_requests > request_limit.to_i
        raise QuotaExceeded, "#{period} upload quota exceeded" if byte_limit.to_i.positive? && next_bytes > byte_limit.to_i
        dataset.update(request_count: next_requests, byte_count: next_bytes, updated_at: clock.call)
      end
    end
  end
end
