Sequel.migration do
  up do
    alter_table :source_documents do
      add_column :principal, String, size: 128, null: false, default: 'system'
      add_index :principal
      add_index [:principal, :created_at]
    end

    alter_table :media_jobs do
      add_foreign_key :staging_media_object_id, :media_objects, on_delete: :set_null
      add_index :staging_media_object_id
    end

    run <<~SQL
      UPDATE source_documents
      SET principal = COALESCE(NULLIF(metadata->>'principal', ''), 'system')
    SQL
    run <<~SQL
      UPDATE media_jobs mj
      SET staging_media_object_id = mo.id
      FROM media_objects mo
      WHERE mj.source = mo.storage_uri
        AND mj.staging_media_object_id IS NULL
    SQL
  end

  down do
    alter_table :media_jobs do
      drop_index :staging_media_object_id
      drop_column :staging_media_object_id
    end
    alter_table :source_documents do
      drop_index [:principal, :created_at]
      drop_index :principal
      drop_column :principal
    end
  end
end
