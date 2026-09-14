Sequel.migration do
  up do
    # Create vector extension if it doesn't exist
    run 'CREATE EXTENSION IF NOT EXISTS vector'

    create_table :embeddings do
      primary_key :id
      foreign_key :source_id, :source_sections, null: false, on_delete: :cascade
      # Vector dimension size (adjust based on embedding model)
      column :vector, 'vector(4096)', null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # NOTE: no vector index is created here because pgvector's ivfflat/hnsw
    # indexes only support up to 2000 dimensions, while qwen3-embedding
    # produces 4096-dimension vectors. Similarity search falls back to exact
    # (sequential) scan, which is fine for small to medium datasets.

    # Composite index for source_id lookups
    add_index :embeddings, :source_id

    # Additional index for faster lookups during similarity search
    add_index :embeddings, :created_at
  end

  down do
    drop_table :embeddings
  end
end
