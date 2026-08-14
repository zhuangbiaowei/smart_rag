Sequel.migration do
  up do
    add_column :source_sections, :metadata, :jsonb, default: '{}', null: false
    add_index :source_sections, :metadata, type: :gin
  end

  down do
    drop_index :source_sections, :metadata
    drop_column :source_sections, :metadata
  end
end
