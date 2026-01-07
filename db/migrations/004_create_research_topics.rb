Sequel.migration do
  up do
    create_table :research_topics do
      primary_key :id
      String :name, null: false, unique: true, size: 255
      String :description, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :research_topics, :name
  end

  down do
    drop_table :research_topics
  end
end
