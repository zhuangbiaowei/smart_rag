Sequel.migration do
  up do
    create_table :source_documents do
      primary_key :id
      String :title, null: false, size: 255
      String :url, text: true
      String :author, size: 255
      Date :publication_date
      String :language, size: 10, default: 'en'
      String :description, text: true
      # 0: pending, 1: completed, 2: failed
      Integer :download_state, default: 0, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # Add index for common queries
    add_index :source_documents, :download_state
    add_index :source_documents, :created_at
    add_index :source_documents, :language
  end

  down do
    drop_table :source_documents
  end
end
