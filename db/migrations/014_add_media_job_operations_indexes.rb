Sequel.migration do
  up do
    add_index :media_jobs, [:status, :started_at]
    add_index :media_jobs, [:status, :finished_at]
  end

  down do
    drop_index :media_jobs, [:status, :finished_at]
    drop_index :media_jobs, [:status, :started_at]
  end
end
