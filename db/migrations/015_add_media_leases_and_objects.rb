Sequel.migration do
  up do
    alter_table :media_jobs do
      add_column :idempotency_key, String, size: 128
      add_column :principal, String, size: 128, null: false, default: 'system'
      add_column :lease_token, String, size: 64
      add_column :heartbeat_at, DateTime
      add_index [:principal, :idempotency_key], unique: true
      add_index [:status, :heartbeat_at]
    end

    create_table :media_objects do
      primary_key :id
      String :content_hash, null: false, size: 128, unique: true
      String :storage_uri, text: true, null: false
      Integer :byte_size, null: false
      Integer :reference_count, null: false, default: 0
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :reference_count
    end

    create_table :media_object_references do
      primary_key :id
      foreign_key :media_object_id, :media_objects, null: false, on_delete: :cascade
      foreign_key :document_id, :source_documents, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index [:media_object_id, :document_id], unique: true, name: :media_object_document_unique
      index :document_id
    end


    create_table :api_rate_limits do
      primary_key :id
      String :principal, null: false, size: 128
      String :period, null: false, size: 16
      DateTime :window_start, null: false
      Integer :request_count, null: false, default: 0
      Bignum :byte_count, null: false, default: 0
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index [:principal, :period, :window_start], unique: true, name: :api_rate_limit_window_unique
    end

    run <<~SQL
      INSERT INTO media_objects (content_hash, storage_uri, byte_size, reference_count)
      SELECT metadata->>'content_hash', metadata->>'storage_uri',
             COALESCE((metadata->>'file_size')::bigint, 0), 0
      FROM source_documents
      WHERE metadata ? 'storage_uri' AND metadata ? 'content_hash'
      ON CONFLICT (content_hash) DO NOTHING
    SQL
    run <<~SQL
      INSERT INTO media_object_references (media_object_id, document_id)
      SELECT mo.id, sd.id
      FROM source_documents sd
      JOIN media_objects mo ON mo.content_hash = sd.metadata->>'content_hash'
      WHERE sd.metadata ? 'storage_uri'
      ON CONFLICT DO NOTHING
    SQL
    run <<~SQL
      UPDATE media_objects mo SET reference_count = refs.count
      FROM (SELECT media_object_id, COUNT(*) AS count FROM media_object_references GROUP BY media_object_id) refs
      WHERE refs.media_object_id = mo.id
    SQL
  end

  down do
    drop_table :api_rate_limits
    drop_table :media_object_references
    drop_table :media_objects
    alter_table :media_jobs do
      drop_index [:status, :heartbeat_at]
      drop_index [:principal, :idempotency_key]
      drop_column :heartbeat_at
      drop_column :lease_token
      drop_column :idempotency_key
      drop_column :principal
    end
  end
end
