Sequel.migration do
  up do
    create_table :search_logs do
      primary_key :id
      String :query, null: false, text: true
      String :search_type, size: 20 # 'vector', 'fulltext', 'hybrid'
      Integer :execution_time_ms
      Integer :results_count
      column :query_vector, 'vector(1024)' # Store query vector for analysis
      column :result_ids, 'integer[]' # Store result IDs for relevance analysis
      column :filters, 'jsonb' # Store search filters
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # Indexes for performance monitoring
    add_index :search_logs, :created_at
    add_index :search_logs, :search_type
    add_index :search_logs, :execution_time_ms

    # GIN index for full-text search on queries
    run "CREATE INDEX search_logs_query_idx ON search_logs USING gin (to_tsvector('simple', query))"

    # Composite index for common analytics queries
    add_index :search_logs, [:search_type, :created_at]
  end

  down do
    drop_table :search_logs
  end
end
