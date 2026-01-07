require_relative "model_base"
require "sequel/plugins/validation_helpers"

module SmartRAG
  module Models
    # SearchLog model for tracking search queries and performance
    class SearchLog < Sequel::Model
      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:search_logs)
      end
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps, update_on_create: false

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(", "))
        instance
      end

      # Validation
      def validate
        super
        validates_presence :query
        validates_max_length 10000, :query  # Reasonable limit for query length
        validates_includes %w[vector fulltext hybrid], :search_type, allow_nil: true
        validates_integer :execution_time_ms, allow_nil: true, greater_than_or_equal_to: 0
        validates_integer :results_count, allow_nil: true, greater_than_or_equal_to: 0
      end

      # Class methods
      class << self
        # Log a search query
        def log(query:, search_type: nil, execution_time_ms: nil, results_count: nil,
                query_vector: nil, result_ids: nil, filters: nil)
          create(
            query: query,
            search_type: search_type,
            execution_time_ms: execution_time_ms,
            results_count: results_count,
            query_vector: query_vector,
            result_ids: result_ids,
            filters: filters.is_a?(Hash) ? filters.to_json : filters
          )
        end

        # Find logs by query type
        def by_search_type(type)
          where(search_type: type)
        end

        # Get slow queries
        def slow_queries(threshold_ms: 100)
          where(Sequel.lit('execution_time_ms IS NOT NULL AND execution_time_ms > ?', threshold_ms))
            .order(Sequel.desc(:execution_time_ms))
        end

        # Get recent searches
        def recent(limit: 50)
          order(Sequel.desc(:created_at)).limit(limit)
        end

        # Get popular queries (by frequency)
        def popular(limit: 20)
          group_and_count(:query)
            .order(Sequel.desc(:count))
            .limit(limit)
        end

        # Get searches with no results
        def with_no_results
          where(results_count: 0).or(results_count: nil)
        end

        # Get searches with many results
        def with_many_results(threshold: 100)
          where(Sequel.lit('results_count > ?', threshold))
        end

        # Get average execution time by search type
        def average_execution_time_by_type
          select(:search_type,
                 Sequel.function(:avg, :execution_time_ms).as(:avg_time),
                 Sequel.function(:count, :*).as(:count))
            .where(Sequel.lit('execution_time_ms IS NOT NULL'))
            .group(:search_type)
            .order(Sequel.desc(:avg_time))
        end

        # Find similar queries (based on vector similarity)
        def find_similar_queries(query_vector, limit: 10)
          return [] unless query_vector

          # Find queries with similar vectors and non-zero results
          where(Sequel.lit('query_vector IS NOT NULL AND results_count > 0'))
            .where(Sequel.lit('query_vector <=> ? < ?', query_vector.to_s, 0.3))
            .order(Sequel.lit('query_vector <=> ?', query_vector.to_s))
            .limit(limit)
        end

        # Get search analytics (by time period)
        def analytics_by_period(start_time:, end_time:)
          where(created_at: start_time..end_time)
            .select(
              Sequel.function(:count, :*).as(:total_searches),
              Sequel.function(:avg, :execution_time_ms).as(:avg_response_time),
              Sequel.function(:sum, Sequel.lit("CASE WHEN results_count > 0 THEN 1 ELSE 0 END")).as(:successful_searches),
              Sequel.function(:sum, Sequel.lit("CASE WHEN results_count = 0 OR results_count IS NULL THEN 1 ELSE 0 END")).as(:failed_searches)
            )
            .first
        end

        # Clean old logs (keep only last N days)
        def cleanup(days_to_keep: 30)
          cutoff_date = Time.now - (days_to_keep * 24 * 60 * 60)
          where(Sequel.lit('created_at < ?', cutoff_date)).delete
        end

        # Export search logs
        def export(start_time:, end_time:, format: :json)
          logs = where(created_at: start_time..end_time).all

          case format
          when :json
            logs.map(&:to_hash).to_json
          when :csv
            # Convert to CSV (simplified)
            require 'csv'
            CSV.generate do |csv|
              csv << [:id, :query, :search_type, :execution_time_ms, :results_count, :created_at]
              logs.each do |log|
                csv << [log.id, log.query, log.search_type, log.execution_time_ms, log.results_count, log.created_at]
              end
            end
          else
            logs
          end
        end
      end

      # Instance methods

      # Check if search was successful (had results)
      def successful?
        results_count && results_count > 0
      end

      # Check if search was slow
      def slow?(threshold_ms: 100)
        execution_time_ms && execution_time_ms > threshold_ms
      end

      # Get filters as hash
      def filters_hash
        begin
          filters.is_a?(String) ? JSON.parse(filters) : filters
        rescue
          {}
        end
      end

      # Get result IDs as array
      def result_ids_array
        return [] unless result_ids
        result_ids.is_a?(String) ? JSON.parse(result_ids) : result_ids
      end

      # Query vector as array
      def query_vector_array
        return nil unless query_vector
        query_vector.to_s.gsub(/[<>]/, '').split(',').map(&:to_f)
      rescue
        nil
      end

      # Log info hash
      def info
        {
          id: id,
          query: query,
          search_type: search_type,
          execution_time_ms: execution_time_ms,
          results_count: results_count,
          successful: successful?,
          slow: slow?,
          created_at: created_at
        }
      end

      # String representation
      def to_s
        "<SearchLog: #{id} - #{query[0..50]}#{query.length > 50 ? '...' : ''} (#{search_type})>"
      end
    end
  end
end
