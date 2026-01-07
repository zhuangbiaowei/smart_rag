Sequel.migration do
  up do
    create_table :section_fts do
      # One-to-one relationship with source_sections
      primary_key :section_id
      foreign_key :document_id, :source_documents, on_delete: :cascade
      String :language, null: false, default: 'en'
      column :fts_title, 'tsvector'
      column :fts_content, 'tsvector'
      column :fts_combined, 'tsvector'
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # Primary composite index for combined search
    add_index :section_fts, :fts_combined, type: :gin
    add_index :section_fts, :language
    add_index :section_fts, :fts_title, type: :gin

    # Partitioned indexes for frequently used languages
    # These improve query performance for language-specific searches
    run 'CREATE INDEX section_fts_gin_zh ON section_fts USING GIN (fts_combined) WHERE language = \'zh\''
    run 'CREATE INDEX section_fts_gin_en ON section_fts USING GIN (fts_combined) WHERE language = \'en\''
    run 'CREATE INDEX section_fts_gin_ja ON section_fts USING GIN (fts_combined) WHERE language = \'ja\''

    # Foreign key index
    add_index :section_fts, :document_id

    # Create trigger function to automatically maintain FTS data
    run <<-SQL
      CREATE OR REPLACE FUNCTION update_section_fts()
      RETURNS TRIGGER AS $$
      DECLARE
          v_language TEXT;
          v_config TEXT;
      BEGIN
          -- Get document language
          SELECT COALESCE(sd.language, 'en') INTO v_language
          FROM source_documents sd
          WHERE sd.id = NEW.document_id;

          -- Get corresponding text search configuration
          SELECT COALESCE(tsc.config_name, 'pg_catalog.simple') INTO v_config
          FROM text_search_configs tsc
          WHERE tsc.language_code = v_language;

          -- Maintain full-text search data
          INSERT INTO section_fts (section_id, document_id, language, fts_title, fts_content, fts_combined)
          VALUES (
              NEW.id,
              NEW.document_id,
              v_language,
              setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.section_title,'')), 'A'),
              setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.content,'')), 'B'),
              setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.section_title,'')), 'A') ||
              setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.content,'')), 'B')
          )
          ON CONFLICT (section_id) DO UPDATE SET
              document_id = NEW.document_id,
              language = v_language,
              fts_title = setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.section_title,'')), 'A'),
              fts_content = setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.content,'')), 'B'),
              fts_combined = setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.section_title,'')), 'A') ||
                            setweight(to_tsvector(v_config::regconfig, COALESCE(NEW.content,'')), 'B'),
              updated_at = CURRENT_TIMESTAMP;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    # Create trigger on source_sections table
    run <<-SQL
      CREATE TRIGGER trigger_update_section_fts
          AFTER INSERT OR UPDATE ON source_sections
          FOR EACH ROW EXECUTE FUNCTION update_section_fts();
    SQL

    # Also create trigger for document language changes
    run <<-SQL
      CREATE OR REPLACE FUNCTION update_section_fts_on_doc_update()
      RETURNS TRIGGER AS $$
      BEGIN
          -- Update FTS for all sections when document language changes
          IF NEW.language IS DISTINCT FROM OLD.language THEN
              UPDATE section_fts
              SET updated_at = CURRENT_TIMESTAMP
              WHERE document_id = NEW.id;
          END IF;
          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<-SQL
      CREATE TRIGGER trigger_update_section_fts_on_doc
          AFTER UPDATE OF language ON source_documents
          FOR EACH ROW EXECUTE FUNCTION update_section_fts_on_doc_update();
    SQL
  end

  down do
    run 'DROP TRIGGER IF EXISTS trigger_update_section_fts_on_doc ON source_documents'
    run 'DROP FUNCTION IF EXISTS update_section_fts_on_doc_update()'
    run 'DROP TRIGGER IF EXISTS trigger_update_section_fts ON source_sections'
    run 'DROP FUNCTION IF EXISTS update_section_fts()'
    drop_table :section_fts
  end
end
