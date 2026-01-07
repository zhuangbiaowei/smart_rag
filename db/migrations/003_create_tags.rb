Sequel.migration do
  up do
    create_table :tags do
      primary_key :id
      String :name, null: false, unique: true, size: 255
      foreign_key :parent_id, :tags, on_delete: :set_null
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :tags, :name
    add_index :tags, :parent_id
  end

  down do
    drop_table :tags
  end
end
