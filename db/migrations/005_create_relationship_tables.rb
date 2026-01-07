Sequel.migration do
  up do
    # Section tags (many-to-many)
    create_table :section_tags do
      foreign_key :section_id, :source_sections, null: false, on_delete: :cascade
      foreign_key :tag_id, :tags, null: false, on_delete: :cascade
      primary_key [:section_id, :tag_id]
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :section_tags, [:section_id, :tag_id], unique: true
    add_index :section_tags, :tag_id

    # Research topic sections (many-to-many)
    create_table :research_topic_sections do
      foreign_key :research_topic_id, :research_topics, null: false, on_delete: :cascade
      foreign_key :section_id, :source_sections, null: false, on_delete: :cascade
      primary_key [:research_topic_id, :section_id]
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :research_topic_sections, [:research_topic_id, :section_id], unique: true
    add_index :research_topic_sections, :section_id

    # Research topic tags (many-to-many)
    create_table :research_topic_tags do
      foreign_key :research_topic_id, :research_topics, null: false, on_delete: :cascade
      foreign_key :tag_id, :tags, null: false, on_delete: :cascade
      primary_key [:research_topic_id, :tag_id]
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :research_topic_tags, [:research_topic_id, :tag_id], unique: true
    add_index :research_topic_tags, :tag_id
  end

  down do
    drop_table :research_topic_tags
    drop_table :research_topic_sections
    drop_table :section_tags
  end
end
