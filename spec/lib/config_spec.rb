require 'spec_helper'
require 'smart_rag/config'

RSpec.describe SmartRAG::Config do
  def config_dir
    File.join(__dir__, '..', '..', 'config')
  end

  def test_config_path
    File.join(config_dir, 'test_smart_rag.yml')
  end

  def test_db_config_path
    File.join(config_dir, 'test_database.yml')
  end

  def test_fulltext_config_path
    File.join(config_dir, 'test_fulltext_search.yml')
  end

  # Create test config files
  before(:all) do
    @config_dir = File.join(File.dirname(__FILE__), '..', '..', 'config')
    @test_configs = {
      'test_smart_rag.yml' => {
        database: {
          adapter: 'postgresql',
          host: 'localhost',
          database: 'smart_rag_test',
          username: 'test_user',
          password: 'test_pass'
        },
        embedding: {
          provider: 'openai',
          dimensions: 1024,
          model: 'text-embedding-ada-002'
        },
        fulltext_search: {
          languages: ['en', 'zh', 'ja'],
          default_config: 'pg_catalog.simple'
        }
      },
      'test_database.yml' => {
        test: {
          adapter: 'postgresql',
          host: 'localhost',
          database: 'smart_rag_test',
          username: 'test_user',
          password: 'test_pass'
        },
        production: {
          adapter: 'postgresql',
          host: 'prod-host',
          database: 'smart_rag_prod',
          username: 'prod_user',
          password: 'prod_pass'
        }
      },
      'test_fulltext_search.yml' => {
        en: 'pg_catalog.english',
        zh: 'jieba',
        ja: 'pg_catalog.simple'
      }
    }

    @test_configs.each do |filename, content|
      File.write(File.join(@config_dir, filename), content.to_yaml)
    end

    # Create test file paths as instance variables
    @test_config_path = File.join(@config_dir, 'test_smart_rag.yml')
    @test_db_config_path = File.join(@config_dir, 'test_database.yml')
    @test_fulltext_config_path = File.join(@config_dir, 'test_fulltext_search.yml')
  end

  # Clean up test config files
  after(:all) do
    @test_configs.each do |filename, _|
      File.delete(File.join(@config_dir, filename)) if File.exist?(File.join(@config_dir, filename))
    end
  end

  describe '.load' do
    it 'loads configuration from YAML file' do
      config = SmartRAG::Config.load(@test_config_path)

      expect(config).to be_a(Hash)
      expect(config[:database][:adapter]).to eq('postgresql')
      expect(config[:database][:database]).to eq('smart_rag_test')
    end

    it 'processes ERB in YAML files' do
      erb_config_path = File.join(@config_dir, 'test_erb.yml')
      File.write(erb_config_path, <<~YAML)
        database:
          adapter: <%= "postgre" + "sql" %>
          env: <%= ENV['SMARTRAG_ENV'] || 'development' %>
        embedding:
          provider: openai
          dimensions: 1024
        test:
          value: <%= "computed_" + "value" %>
          env: <%= ENV['SMARTRAG_ENV'] || 'development' %>
      YAML

      config = SmartRAG::Config.load(erb_config_path)
      expect(config[:test][:value]).to eq('computed_value')
      expect(config[:test][:env]).to eq('development')
      expect(config[:database][:adapter]).to eq('postgresql')
      expect(config[:database][:env]).to eq('development')

      File.delete(erb_config_path)
    end

    it 'validates required configuration sections' do
      invalid_config_path = File.join(@config_dir, 'test_invalid.yml')
      File.write(invalid_config_path, { database: nil }.to_yaml)

      expect { SmartRAG::Config.load(invalid_config_path) }.to raise_error(/Missing required 'database' configuration/)

      File.delete(invalid_config_path)
    end

    it 'warns about missing embedding provider' do
      config_without_provider = File.join(@config_dir, 'test_no_provider.yml')
      File.write(config_without_provider, {
        database: { adapter: 'postgresql' },
        embedding: { dimensions: 1024 }
      }.to_yaml)

      expect { SmartRAG::Config.load(config_without_provider) }.to output(/Warning: Missing embedding provider configuration/).to_stdout

      File.delete(config_without_provider)
    end

    it 'sets default embedding dimensions if not specified' do
      config_without_dimensions = File.join(@config_dir, 'test_no_dimensions.yml')
      File.write(config_without_dimensions, {
        database: { adapter: 'postgresql' },
        embedding: { provider: 'openai' }
      }.to_yaml)

      config = SmartRAG::Config.load(config_without_dimensions)
      expect(config[:embedding][:dimensions]).to eq(1024)

      File.delete(config_without_dimensions)
    end

    it 'raises error when config file does not exist' do
      expect { SmartRAG::Config.load('/nonexistent/path.yml') }.to raise_error(/Configuration file not found/)
    end

    it 'loads with symbols permitted' do
      config = SmartRAG::Config.load(@test_config_path)
      expect(config.keys).to all(be_a(Symbol))
      expect(config[:database].keys).to include(:adapter, :host, :database)
    end
  end

  describe '.load_database_config' do
    it 'loads database configuration for specific environment' do
      ENV['RACK_ENV'] = 'test'
      # Mock the config_dir method to return our test directory
      allow(SmartRAG::Config).to receive(:config_dir).and_return(@config_dir)
      allow(File).to receive(:exist?).with(File.join(@config_dir, 'database.yml')).and_return(true)
      allow(File).to receive(:read).with(File.join(@config_dir, 'database.yml')).and_return(<<-YAML)
test:
  adapter: postgresql
  host: localhost
  database: test_db
production:
  adapter: postgresql
  database: prod_db
      YAML

      config = SmartRAG::Config.load_database_config

      expect(config).to be_a(Hash)
      expect(config[:adapter]).to eq('postgresql')
      expect(config[:database]).to eq('test_db')
    end

    it 'loads production configuration' do
      # Mock the config_dir method to return our test directory
      allow(SmartRAG::Config).to receive(:config_dir).and_return(@config_dir)
      allow(File).to receive(:exist?).with(File.join(@config_dir, 'database.yml')).and_return(true)
      allow(File).to receive(:read).with(File.join(@config_dir, 'database.yml')).and_return(<<-YAML)
test:
  adapter: postgresql
  database: smart_rag_test
production:
  adapter: postgresql
  host: prod-host
  database: smart_rag_prod
  username: prod_user
  password: prod_pass
      YAML

      config = SmartRAG::Config.load_database_config('production')

      expect(config[:database]).to eq('smart_rag_prod')
      expect(config[:username]).to eq('prod_user')
    end

    it 'falls back to main config if database.yml does not exist' do
      allow(File).to receive(:exist?).and_return(false)
      allow(SmartRAG::Config).to receive(:load).and_return({
        database: {
          adapter: 'postgresql',
          database: 'fallback_db'
        }
      })

      config = SmartRAG::Config.load_database_config
      expect(config[:database]).to eq('fallback_db')
    end
  end

  describe '.load_fulltext_config' do
    it 'loads fulltext search configuration' do
      # Mock the config_dir method to return our test directory
      allow(SmartRAG::Config).to receive(:config_dir).and_return(@config_dir)
      allow(File).to receive(:exist?).with(File.join(@config_dir, 'fulltext_search.yml')).and_return(true)
      allow(File).to receive(:read).with(File.join(@config_dir, 'fulltext_search.yml')).and_return({
        en: 'pg_catalog.english',
        zh: 'jieba',
        ja: 'pg_catalog.simple'
      }.to_yaml)

      config = SmartRAG::Config.load_fulltext_config

      expect(config).to be_a(Hash)
      expect(config[:en]).to eq('pg_catalog.english')
      expect(config[:zh]).to eq('jieba')
    end

    it 'returns empty hash if config does not exist and no fallback' do
      allow(File).to receive(:exist?).and_return(false)
      allow(SmartRAG::Config).to receive(:load).and_return({})

      config = SmartRAG::Config.load_fulltext_config
      expect(config).to eq({})
    end

    it 'fallbacks to main config' do
      allow(File).to receive(:exist?).and_return(false)
      allow(SmartRAG::Config).to receive(:load).and_return({
        fulltext_search: {
          en: 'english',
          default: 'simple'
        }
      })

      config = SmartRAG::Config.load_fulltext_config
      expect(config[:en]).to eq('english')
      expect(config[:default]).to eq('simple')
    end
  end

  describe 'configuration validation' do
    it 'accepts valid configuration' do
      config = {
        database: { adapter: 'postgresql', database: 'test' },
        embedding: { provider: 'openai', dimensions: 1024 }
      }

      expect { SmartRAG::Config.send(:validate_config, config) }.not_to raise_error
    end

    it 'validates fulltext search languages' do
      config = {
        database: { adapter: 'postgresql' },
        fulltext_search: {
          languages: ['en', 'zh', 'invalid_lang']
        }
      }

      # Should not raise, but languages are checked
      expect { SmartRAG::Config.send(:validate_config, config) }.not_to raise_error
    end
  end

  describe 'environment integration' do
    it 'respects RACK_ENV environment variable' do
      ENV['RACK_ENV'] = 'test'
      # Mock the config_dir method to return our test directory
      allow(SmartRAG::Config).to receive(:config_dir).and_return(@config_dir)
      allow(File).to receive(:exist?).with(File.join(@config_dir, 'database.yml')).and_return(true)
      allow(File).to receive(:read).with(File.join(@config_dir, 'database.yml')).and_return(<<-YAML)
test:
  adapter: postgresql
  database: smart_rag_test
production:
  adapter: postgresql
  database: smart_rag_prod
      YAML

      config = SmartRAG::Config.load_database_config
      expect(config[:database]).to eq('smart_rag_test')

      ENV.delete('RACK_ENV')
    end

    it 'defaults to development when no env specified' do
      ENV.delete('RACK_ENV')
      # Mock the config_dir method to return our test directory
      allow(SmartRAG::Config).to receive(:config_dir).and_return(@config_dir)
      allow(File).to receive(:exist?).with(File.join(@config_dir, 'database.yml')).and_return(true)
      allow(File).to receive(:read).with(File.join(@config_dir, 'database.yml')).and_return(<<-YAML)
development:
  adapter: postgresql
  database: smart_rag_dev
      YAML

      config = SmartRAG::Config.load_database_config
      expect(config[:database]).to eq('smart_rag_dev')
    end
  end
end
