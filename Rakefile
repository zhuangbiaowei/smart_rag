# Remove bundler/gem_tasks to avoid conflicts

# Load environment variables from .env file if it exists

begin
  require "dotenv"
  Dotenv.load
  puts "Loaded environment variables from .env file"
rescue LoadError
  # dotenv not available, skip loading
  puts "Note: dotenv gem not found. Install with: gem install dotenv"
rescue => e
  puts "Warning: Could not load .env file: #{e.message}"
end

require "rbconfig"

def windows?
  /mswin|mingw|cygwin/i.match?(RbConfig::CONFIG["host_os"])
end

def running_as_root?
  Process.respond_to?(:uid) && Process.uid == 0
end

def load_db_config
  require_relative "lib/smart_rag/config"
  SmartRAG::Config.load[:database]
rescue => e
  puts "Warning: Could not load config: #{e.message}"
  puts "Using environment variables instead..."

  {
    adapter: "postgresql",
    host: ENV["SMARTRAG_DB_HOST"] || "localhost",
    port: ENV["SMARTRAG_DB_PORT"] || 5432,
    database: ENV["SMARTRAG_DB_NAME"] || "smart_rag_development",
    username: ENV["SMARTRAG_DB_USER"] || "postgres",
    password: ENV["SMARTRAG_DB_PASSWORD"],
    pool: 5,
    encoding: "UTF8",
    timeout: 5000,
  }
end

RSpec::Core::RakeTask.new(:spec) if defined?(RSpec)

task :default => :spec if Rake::Task.task_defined?(:spec)

namespace :db do
  desc "Create database"
  task :create do
    require "sequel"
    config = load_db_config
    database = config.delete(:database)

    # Try to create the database using psql command for better compatibility
    host = config[:host] || "localhost"
    port = config[:port] || 5432
    username = config[:username] || "postgres"

    if host == "localhost" && running_as_root? && !windows?
      # Running as root, try with sudo
      begin
        system("sudo", "-u", username, "createdb", "-h", host, "-p", port.to_s, database)
        if $?.success?
          puts "Database #{database} created"
          next
        end
      rescue
        # Fall through to Sequel method
      end
    end

    begin
      # Remove extensions from config when connecting to postgres database
      # pgvector extension shouldn't be loaded when just creating a database
      connect_config = config.dup
      connect_config.delete(:extensions)
      db = Sequel.connect(connect_config.merge(database: "postgres"))
      db.execute("CREATE DATABASE #{database}")
      db.disconnect
      puts "Database #{database} created"
    rescue => e
      puts "Failed to create database: #{e.message}"
      puts "You may need to:"
      puts "  1. Ensure PostgreSQL is running"
      puts "  2. Create a .env file with database credentials"
      puts "  3. Use sudo -u postgres rake db:create if running as root"
      exit 1
    end
  end

  desc "Drop database"
  task :drop do
    require "sequel"
    config = load_db_config
    database = config.delete(:database)

    host = config[:host] || "localhost"
    port = config[:port] || 5432
    username = config[:username] || "postgres"

    if host == "localhost" && running_as_root? && !windows?
      # Running as root, try with sudo
      begin
        system("sudo", "-u", username, "dropdb", "-h", host, "-p", port.to_s, "--if-exists", database)
        if $?.success?
          puts "Database #{database} dropped"
          next
        end
      rescue
        # Fall through to Sequel method
      end
    end

    begin
      # Remove extensions from config when connecting to postgres database
      connect_config = config.dup
      connect_config.delete(:extensions)
      db = Sequel.connect(connect_config.merge(database: "postgres"))
      db.execute("DROP DATABASE IF EXISTS #{database}")
      db.disconnect
      puts "Database #{database} dropped"
    rescue => e
      puts "Failed to drop database: #{e.message}"
      exit 1
    end
  end

  desc "Run migrations"
  task :migrate do
    require "sequel"
    Sequel.extension :migration
    # Remove extensions from config - they're installed via SQL, not Sequel
    config = load_db_config
    config.delete(:extensions)
    db = Sequel.connect(config)

    # Enable extensions
    db.run "CREATE EXTENSION IF NOT EXISTS vector"
    db.run "CREATE EXTENSION IF NOT EXISTS pg_jieba"

    migrations_dir = File.join(__dir__, "db", "migrations")
    Sequel::Migrator.run(db, migrations_dir)

    puts "Migrations completed"
    db.disconnect
  end

  desc "Rollback migrations"
  task :rollback, [:steps] do |t, args|
    args.with_defaults(steps: 1)

    require "sequel"
    Sequel.extension :migration
    config = load_db_config
    config.delete(:extensions)
    db = Sequel.connect(config)

    migrations_dir = File.join(__dir__, "db", "migrations")
    Sequel::Migrator.run(db, migrations_dir, target: -args[:steps].to_i)

    puts "Rolled back #{args[:steps]} migration(s)"
    db.disconnect
  end

  desc "Seed database with initial data"
  task :seed do
    require "sequel"
    config = load_db_config
    config.delete(:extensions)
    db = Sequel.connect(config)

    seeds_file = File.join(__dir__, "db", "seeds", "text_search_configs.sql")
    if File.exist?(seeds_file)
      sql = File.read(seeds_file)
      db.run sql
      puts "Database seeded"
    else
      puts "Seeds file not found: #{seeds_file}"
    end

    db.disconnect
  end

  desc "Reset database (drop, create, migrate, seed)"
  task :reset => [:drop, :create, :migrate, :seed]
end

namespace :test do
  desc "Setup test database"
  task :db_setup do
    # Configure test environment
    ENV["RACK_ENV"] = "test"

    # This will be handled by spec_helper
    puts "Test database will be set up by spec_helper"
  end

  desc "Run tests"
  task :run => :db_setup do
    if Rake::Task.task_defined?(:spec)
      Rake::Task["spec"].execute
    else
      puts "RSpec is not available. Install with: gem install rspec"
    end
  end
end

# Only define build tasks if we have a VERSION constant
desc "Build gem"
task :build do
  # Simple gem build without relying on Bundler tasks
  sh "gem build smart_rag.gemspec"
end

# Simple install task that doesn't require loading the gem
desc "Install gem locally"
task :install => :build do
  gemspec_file = "smart_rag.gemspec"
  if File.exist?(gemspec_file)
    # Extract version from gemspec
    require "yaml"
    spec = YAML.load_file(gemspec_file)
    version = spec[:version] || ENV["VERSION"] || "0.1.0"

    sh "gem install ./smart_rag-#{version}.gem"
  else
    puts "Gemspec file not found: #{gemspec_file}"
  end
end
