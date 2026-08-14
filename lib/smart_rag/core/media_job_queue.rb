# frozen_string_literal: true

require 'json'
require 'digest'
require 'securerandom'
require 'time'

module SmartRAG
  module Core
    class MediaJobQueue
      class IdempotencyConflict < StandardError; end

      STATUSES = %w[queued processing completed partial failed canceled].freeze
      TERMINAL_STATUSES = %w[completed partial failed canceled].freeze

      def initialize(db:, handler:, clock: -> { Time.now }, heartbeat_interval_seconds: 30)
        @db = db
        @handler = handler
        @clock = clock
        @heartbeat_interval_seconds = [heartbeat_interval_seconds.to_f, 0.1].max
      end

      def enqueue(operation:, source:, options: {}, max_attempts: 3, idempotency_key: nil,
                  principal: 'system', staging_media_object_id: nil)
        ensure_available!
        key = normalize_idempotency_key(idempotency_key)
        owner = normalize_principal(principal)
        serialized_options = serializable_options(options)
        fingerprint = request_fingerprint(operation, source, serialized_options)
        existing = key && db[:media_jobs].where(principal: owner, idempotency_key: key).first
        return deduplicate(existing, fingerprint) if existing

        attributes = {
          operation: operation.to_s, source: source.to_s,
          options: JSON.generate(serialized_options), request_fingerprint: fingerprint,
          status: 'queued', attempts: 0, max_attempts: max_attempts,
          idempotency_key: key, principal: owner, staging_media_object_id: staging_media_object_id,
          available_at: clock.call, created_at: clock.call, updated_at: clock.call
        }
        id = db.transaction(savepoint: true) { db[:media_jobs].insert(attributes) }
        job(id)
      rescue Sequel::UniqueConstraintViolation
        raise unless key
        existing = db[:media_jobs].where(principal: owner, idempotency_key: key).first
        existing ? deduplicate(existing, fingerprint) : raise
      end

      def job(id, principal: nil)
        ensure_available!
        row = scoped_jobs(principal).where(id: id.to_i).first
        row && normalize(row)
      end

      def list(status: nil, limit: 20, offset: 0, principal: nil)
        ensure_available!
        statuses = normalize_statuses(status)
        dataset = scoped_jobs(principal)
        dataset = dataset.where(status: statuses) unless statuses.empty?
        total = dataset.count
        jobs = dataset.order(Sequel.desc(:created_at)).limit(clamp(limit, 1, 100), [offset.to_i, 0].max)
                      .all.map { |row| normalize(row) }
        { jobs: jobs, total: total, limit: clamp(limit, 1, 100), offset: [offset.to_i, 0].max }
      end

      def cancel(id, principal: nil)
        mutate_job(id, principal: principal) do |row|
          next transition_error(row, 'only queued jobs can be canceled') unless row[:status] == 'queued'

          db[:media_jobs].where(id: row[:id]).update(
            status: 'canceled', error: nil, finished_at: clock.call, updated_at: clock.call
          )
          cleanup_source(row, parse_json(row[:options]))
          job(row[:id])
        end
      end

      def retry_job(id, principal: nil)
        mutate_job(id, principal: principal) do |row|
          next transition_error(row, 'only failed jobs can be retried') unless row[:status] == 'failed'
          options = parse_json(row[:options]) || {}
          if (options['delete_source_after'] || options[:delete_source_after]) && !File.file?(row[:source])
            next transition_error(row, 'media job source is no longer available')
          end

          db[:media_jobs].where(id: row[:id]).update(
            status: 'queued', attempts: 0, result: nil, error: nil, available_at: clock.call,
            started_at: nil, finished_at: nil, heartbeat_at: nil, lease_token: nil, updated_at: clock.call
          )
          job(row[:id])
        end
      end

      def recover_stale(timeout_seconds: 900)
        ensure_available!
        cutoff = clock.call - [timeout_seconds.to_i, 1].max
        db[:media_jobs].where(status: 'processing')
                       .where { Sequel.function(:coalesce, :heartbeat_at, :started_at) < cutoff }.update(
          status: 'queued', error: 'worker lease expired; job requeued', available_at: clock.call,
          started_at: nil, heartbeat_at: nil, lease_token: nil, updated_at: clock.call
        )
      end

      def prune(retention_seconds: 604_800)
        ensure_available!
        cutoff = clock.call - [retention_seconds.to_i, 0].max
        rows = db[:media_jobs].where(status: TERMINAL_STATUSES).where { finished_at < cutoff }.all
        rows.each { |row| cleanup_source(row, parse_json(row[:options])) }
        db[:media_jobs].where(id: rows.map { |row| row[:id] }).delete
      end

      def statistics(stale_after_seconds: 900, principal: nil)
        ensure_available!
        counts = STATUSES.to_h { |status| [status.to_sym, 0] }
        dataset = scoped_jobs(principal)
        dataset.group_and_count(:status).all.each do |row|
          counts[row[:status].to_sym] = row[:count].to_i
        end
        now = clock.call
        oldest = dataset.where(status: 'queued').min(:created_at)
        stale_cutoff = now - [stale_after_seconds.to_i, 1].max
        {
          counts: counts,
          total: counts.values.sum,
          oldest_queued_age_seconds: oldest ? [(now - oldest).round, 0].max : nil,
          stale_processing: dataset.where(status: 'processing')
                               .where { Sequel.function(:coalesce, :heartbeat_at, :started_at) < stale_cutoff }.count
        }
      end

      def run_one
        row = claim
        return nil unless row

        options = parse_json(row[:options])
        result = with_heartbeat(row) do
          handler.call(row[:operation].to_sym, row[:source], symbolize_keys(options))
        end
        finish(row, result, options)
      rescue StandardError => e
        raise unless row
        fail_or_retry(row, e)
      end

      def run(limit: 1)
        Array.new(limit.to_i.clamp(1, 100)).filter_map { run_one }
      end

      private

      attr_reader :db, :handler, :clock, :heartbeat_interval_seconds

      def claim
        row = nil
        db.transaction do
          dataset = db[:media_jobs].where(status: 'queued')
                                   .where { available_at <= Sequel.function(:clock_timestamp) }
                                   .order(:created_at).for_update.skip_locked
          row = dataset.first
          if row
            lease_token = SecureRandom.hex(16)
            db[:media_jobs].where(id: row[:id]).update(
              status: 'processing', attempts: row[:attempts].to_i + 1,
              started_at: clock.call, heartbeat_at: clock.call, lease_token: lease_token,
              updated_at: clock.call, error: nil
            )
            row = db[:media_jobs].where(id: row[:id]).first
          end
        end
        row
      end

      def finish(row, result, options)
        status = result[:status].to_s == 'partial' ? 'partial' : 'completed'
        updated = leased_job(row).update(
          status: status, result: JSON.generate(result), finished_at: clock.call,
          heartbeat_at: nil, lease_token: nil, updated_at: clock.call
        )
        raise 'media job lease lost before completion' if updated.zero?
        cleanup_source(row, options)
        job(row[:id])
      end

      def fail_or_retry(row, error)
        attempts = row[:attempts].to_i
        max_attempts = row[:max_attempts].to_i
        if attempts < max_attempts
          updated = leased_job(row).update(
            status: 'queued', error: "#{error.class}: #{error.message}",
            available_at: clock.call + (2**attempts), heartbeat_at: nil, lease_token: nil,
            updated_at: clock.call
          )
        else
          updated = leased_job(row).update(
            status: 'failed', error: "#{error.class}: #{error.message}",
            finished_at: clock.call, heartbeat_at: nil, lease_token: nil, updated_at: clock.call
          )
        end
        raise 'media job lease lost while recording failure' if updated.zero?
        job(row[:id])
      end

      def with_heartbeat(row)
        mutex = Mutex.new
        condition = ConditionVariable.new
        stopped = false
        thread = Thread.new do
          loop do
            mutex.synchronize { condition.wait(mutex, heartbeat_interval_seconds) unless stopped }
            break if mutex.synchronize { stopped }
            break if heartbeat(row).zero?
          end
        end
        yield
      ensure
        mutex&.synchronize do
          stopped = true
          condition.broadcast
        end
        thread&.join
      end

      def heartbeat(row)
        leased_job(row).update(heartbeat_at: clock.call, updated_at: clock.call)
      end

      def leased_job(row)
        db[:media_jobs].where(id: row[:id], status: 'processing', lease_token: row[:lease_token])
      end

      def normalize(row)
        row.merge(options: parse_json(row[:options]), result: parse_json(row[:result]))
      end

      def parse_json(value)
        return value if value.is_a?(Hash)
        return nil if value.nil?
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def serializable_options(options)
        serialize(options)
      end

      def request_fingerprint(operation, source, options)
        payload = {
          'operation' => operation.to_s,
          'source' => source.to_s,
          'options' => canonicalize(options)
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.to_h do |key|
            original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
            [key, canonicalize(value[original_key])]
          end
        when Array then value.map { |item| canonicalize(item) }
        else value
        end
      end

      def deduplicate(existing, fingerprint)
        unless existing[:request_fingerprint].to_s == fingerprint
          raise IdempotencyConflict, 'idempotency key was already used with a different request payload'
        end
        normalize(existing).merge(deduplicated: true)
      end

      def serialize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            next if item.respond_to?(:call) || item.respond_to?(:extract)
            result[key.to_s] = serialize(item)
          end
        when Array then value.map { |item| serialize(item) }
        when Symbol then value.to_s
        when Time then value.iso8601
        else value
        end
      end

      def symbolize_keys(hash)
        return hash.map { |value| value.is_a?(Hash) ? symbolize_keys(value) : value } if hash.is_a?(Array)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value.is_a?(Hash) || value.is_a?(Array) ? symbolize_keys(value) : value
        end
      end

      def ensure_available!
        raise 'media job queue requires a database connection' unless db
        raise 'media_jobs table is missing; run database migrations' unless db.table_exists?(:media_jobs)
      end

      def mutate_job(id, principal: nil)
        ensure_available!
        result = nil
        db.transaction do
          row = scoped_jobs(principal).where(id: id.to_i).for_update.first
          result = row ? yield(row) : nil
        end
        result
      end

      def transition_error(row, message)
        normalize(row).merge(transition_error: message)
      end

      def normalize_statuses(status)
        values = Array(status).flat_map { |value| value.to_s.split(',') }.reject(&:empty?)
        invalid = values - STATUSES
        raise ArgumentError, "invalid media job status: #{invalid.join(', ')}" unless invalid.empty?
        values
      end

      def clamp(value, minimum, maximum)
        [[value.to_i, minimum].max, maximum].min
      end

      def normalize_idempotency_key(value)
        key = value.to_s.strip
        return nil if key.empty?
        raise ArgumentError, 'idempotency_key exceeds 128 characters' if key.length > 128
        key
      end

      def normalize_principal(value)
        principal = value.to_s.strip
        principal = 'system' if principal.empty?
        raise ArgumentError, 'principal exceeds 128 characters' if principal.length > 128
        principal
      end

      def scoped_jobs(principal)
        dataset = db[:media_jobs]
        principal.to_s.empty? ? dataset : dataset.where(principal: normalize_principal(principal))
      end

      def cleanup_source(row, options)
        return unless options && (options['delete_source_after'] || options[:delete_source_after])
        File.delete(row[:source]) if File.file?(row[:source])
      rescue SystemCallError
        nil
      end
    end
  end
end
