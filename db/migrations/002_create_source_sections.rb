Sequel.migration do
  up do
    create_table :source_sections do
      primary_key :id
      foreign_key :document_id, :source_documents, null: false, on_delete: :cascade
      String :content, text: true, null: false
      String :section_title, size: 500
      Integer :section_number, default: 0
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :source_sections, :document_id
    add_index :source_sections, :section_number
  end

  down do
    drop_table :source_sections
  end
end
