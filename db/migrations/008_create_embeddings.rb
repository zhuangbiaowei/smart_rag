Sequel.migration do
  up do
    # Create vector extension if it doesn't exist
    run 'CREATE EXTENSION IF NOT EXISTS vector'

    create_table :embeddings do
      primary_key :id
      foreign_key :source_id, :source_sections, null: false, on_delete: :cascade
      # Vector dimension size (adjust based on embedding model)
      column :vector, 'vector(1024)', null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # Create IVFFLAT index for approximate nearest neighbor search
    # IVFFLAT provides good accuracy with fast search
    run 'CREATE INDEX idx_embedding_vector ON embeddings USING ivfflat (vector vector_cosine_ops) WITH (lists = 100)'

    # Composite index for source_id lookups
    add_index :embeddings, :source_id

    # Additional index for faster lookups during similarity search
    add_index :embeddings, :created_at
  end

  down do
    drop_table :embeddings
  end
end
