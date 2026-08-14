Sequel.migration do
  up do
    create_table :media_jobs do
      primary_key :id
      String :operation, null: false, size: 32
      String :source, text: true, null: false
      column :options, :jsonb, default: '{}', null: false
      String :status, null: false, size: 20, default: 'queued'
      Integer :attempts, null: false, default: 0
      Integer :max_attempts, null: false, default: 3
      column :result, :jsonb
      String :error, text: true
      DateTime :available_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :started_at
      DateTime :finished_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index [:status, :available_at]
    end
  end

  down do
    drop_table :media_jobs
  end
end
