Sequel.migration do
  up do
    add_column :source_documents, :metadata, :jsonb, default: '{}'
    add_index :source_documents, :metadata, type: :gin
  end

  down do
    drop_column :source_documents, :metadata
  end
end
