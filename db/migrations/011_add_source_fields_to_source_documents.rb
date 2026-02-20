Sequel.migration do
  up do
    add_column :source_documents, :source_type, String, size: 50, default: 'manual'
    add_column :source_documents, :source_uri, String, text: true
    add_column :source_documents, :content_hash, String, size: 128

    add_index :source_documents, :source_type
    add_index :source_documents, :source_uri
    add_index :source_documents, :content_hash
    add_index :source_documents, [:source_uri, :content_hash]
  end

  down do
    drop_index :source_documents, [:source_uri, :content_hash]
    drop_index :source_documents, :content_hash
    drop_index :source_documents, :source_uri
    drop_index :source_documents, :source_type

    drop_column :source_documents, :content_hash
    drop_column :source_documents, :source_uri
    drop_column :source_documents, :source_type
  end
end
