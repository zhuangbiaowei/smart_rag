# Database helper methods for tests
module DatabaseHelpers
  def self.test_db_config
    @test_db_config ||= {
      adapter: 'postgresql',
      host: ENV['SMARTRAG_TEST_DB_HOST'] || 'localhost',
      port: ENV['SMARTRAG_TEST_DB_PORT'] || 5432,
      database: ENV['SMARTRAG_TEST_DB_NAME'] || 'smart_rag_test',
      username: ENV['SMARTRAG_TEST_DB_USER'] || 'postgres',
      password: ENV['SMARTRAG_TEST_DB_PASSWORD'],
      pool: 5,
      encoding: 'UTF8',
      timeout: 5000
    }
  end

  def self.test_config
    @test_config ||= {
      database: test_db_config,
      embedding: {
        provider: 'mock',
        dimensions: 1024
      },
      fulltext_search: {
        default_language: 'en',
        max_results: 100
      },
      chunking: {
        max_chars: 4000,
        overlap: 100
      },
      llm: {
        provider: 'mock'
      }
    }
  end

  def self.setup_test_database
    puts "Setting up test database..."

    # Connect to test database
    db = Sequel.connect(test_db_config)
    SmartRAG.db = db

    # Also set database for models since they might be loaded already
    if defined?(SmartRAG::Models)
      SmartRAG::Models.db = db
    end

    # Enable extensions
    begin
      db.run 'CREATE EXTENSION IF NOT EXISTS vector'
      db.run 'CREATE EXTENSION IF NOT EXISTS pg_jieba'
    rescue => e
      puts "Warning: Could not create some extensions: #{e.message}"
    end

    # Run migrations
    Sequel.extension :migration
    migration_dir = File.expand_path('../../db/migrations', __dir__)
    Sequel::Migrator.run(db, migration_dir)

    puts "Test database setup complete!"
  rescue => e
    puts "Error setting up test database: #{e.message}"
    puts "Make sure PostgreSQL is running and credentials are correct"
    puts "Database config: #{test_db_config.inspect}"
    raise
  end

  def self.clean_test_database
    puts "Cleaning up test database..."

    # Drop test tables
    if SmartRAG.db
      SmartRAG.db.disconnect
    end
  end

  def self.fixture_path(filename)
    File.expand_path(File.join(__dir__, '..', 'fixtures', filename))
  end

  def self.sample_document_path
    fixture_path('sample_documents')
  end

  def self.load_fixture(fixture_name)
    path = fixture_path("#{fixture_name}.yml")
    YAML.load_file(path) if File.exist?(path)
  end
end
