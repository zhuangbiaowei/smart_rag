require 'sequel'
require 'database_cleaner-sequel'
require 'factory_bot'
require 'pry'

# Load environment variables from .env file
begin
  require 'dotenv'
  Dotenv.load
  puts "Loaded environment variables from .env file"
rescue LoadError
  puts "Note: dotenv gem not found"
end

# Load test configuration
ENV['RACK_ENV'] = 'test'

# Load helpers first (needed for database setup)
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

# Set up database connection BEFORE loading anything that depends on it
# Sequel models need database connection when they are defined
test_config = DatabaseHelpers.test_db_config
db = Sequel.connect(test_config)
puts "Connected to test database: #{test_config[:database]}"

# Enable extensions
begin
  db.run 'CREATE EXTENSION IF NOT EXISTS vector'
  db.run 'CREATE EXTENSION IF NOT EXISTS pg_jieba'
rescue => e
  puts "Warning: Could not create some extensions: #{e.message}"
end

# Run migrations
Sequel.extension :migration
migration_dir = File.expand_path('../db/migrations', __dir__)
if Dir.exist?(migration_dir)
  Sequel::Migrator.run(db, migration_dir)
  puts "Database migrations completed"
end

# Now load SmartRAG (after database is set up)
require 'smart_rag'
SmartRAG.db = db
require_relative '../lib/smart_rag/models'
SmartRAG::Models.db = db

# Helper method to check if pg_jieba extension is available
def pg_jieba_available?
  @pg_jieba_available ||= begin
    SmartRAG.db.fetch("SELECT to_tsvector('public.jiebacfg', '测试')").first
    true
  rescue
    false
  end
end

# Configure Database Cleaner
DatabaseCleaner[:sequel, db: db].strategy = :transaction

RSpec.configure do |config|
  # Basic configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods
  config.before(:suite) do
    FactoryBot.find_definitions
  end

  # Database cleaner configuration
  config.before(:each) do
    DatabaseCleaner[:sequel, db: db].start
  end

  config.after(:each) do
    DatabaseCleaner[:sequel, db: db].clean
  end

  # Include DatabaseHelpers in all test groups
  config.include DatabaseHelpers

  # After suite cleanup
  config.after(:suite) do
    db.disconnect
    puts "Test database disconnected"
  end
end
