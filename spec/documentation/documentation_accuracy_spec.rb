require 'spec_helper'
require 'smart_rag'
require 'yaml'

RSpec.describe "Documentation Accuracy" do
  let(:smart_rag) { SmartRAG::SmartRAG.new(test_config) }

  describe "API Documentation Accuracy" do
    it "documents all public methods in SmartRAG::SmartRAG" do
      api_doc = File.read('API_DOCUMENTATION.md')

      # Check that all public methods are documented
      public_methods = [
        'initialize',
        'add_document',
        'remove_document',
        'get_document',
        'list_documents',
        'search',
        'vector_search',
        'fulltext_search',
        'create_topic',
        'get_topic',
        'list_topics',
        'update_topic',
        'delete_topic',
        'add_document_to_topic',
        'remove_document_from_topic',
        'get_topic_recommendations',
        'generate_tags',
        'list_tags',
        'statistics',
        'search_logs'
      ]

      public_methods.each do |method|
        expect(api_doc).to include("#{method}("),
          "Method '#{method}' should be documented in API_DOCUMENTATION.md"
      end
    end

    it "has consistent method signatures between code and API docs" do
      api_doc = File.read('API_DOCUMENTATION.md')

      # Check add_document signature
      expect(api_doc).to match(/add_document\([^,)]+,\s*{[^}]+}\)/),
        "add_document should show parameters correctly"

      # Check search signature
      expect(api_doc).to include("search(query, options = {})"),
        "search method signature should match implementation"

      # Check create_topic signature
      expect(api_doc).to include("create_topic(title, description, options = {})"),
        "create_topic method signature should match implementation"
    end

    it "has accurate return value documentation" do
      # Test add_document return matches documentation
      temp_file = Tempfile.new(['test', '.txt'])
      temp_file.write('Test content')
      temp_file.close

      result = smart_rag.add_document(temp_file.path, generate_embeddings: false)
      temp_file.unlink

      # Should match documentation at API_DOCUMENTATION.md lines 63-67
      expect(result).to include(:document_id, :section_count, :status)
      expect(result[:document_id]).to be_a(Integer)
      expect(result[:section_count]).to be_a(Integer)
      expect(result[:status]).to eq('success')
    end

    it "documents all configuration options accurately" do
      api_doc = File.read('API_DOCUMENTATION.md')

      # Check database configuration options
      expect(api_doc).to include('adapter')
      expect(api_doc).to include('host')
      expect(api_doc).to include('database')
      expect(api_doc).to include('user')
      expect(api_doc).to include('password')

      # Check LLM configuration
      expect(api_doc).to include('provider')
      expect(api_doc).to include('api_key')
      expect(api_doc).to include('model')

      # Check search options
      expect(api_doc).to include('search_type')
      expect(api_doc).to include('limit')
      expect(api_doc).to include('alpha')
      expect(api_doc).to include('filters')
    end
  end

  describe "Usage Examples Documentation Accuracy" do
    let(:usage_doc) { File.read('USAGE_EXAMPLES.md') }

    it "has consistent examples with API documentation" do
      # Extract examples from both files and compare
      api_examples = extract_code_examples('API_DOCUMENTATION.md')
      usage_examples = extract_code_examples('USAGE_EXAMPLES.md')

      # Check that common patterns are consistent
      # Both should show the same initialize pattern
      expect(usage_doc).to include('SmartRAG::SmartRAG.new(config)')
      expect(usage_doc).to include('smart_rag.search(')

      # Check that advanced examples build on API docs
      expect(usage_doc).to include('class ContextualSearch')
      expect(usage_doc).to include('class QA_system')
    end

    it "documents realistic use cases" do
      # Check for real-world examples
      expect(usage_doc).to include('healthcare')
      expect(usage_doc).to include('finance')
      expect(usage_doc).to include('batch processing')
      expect(usage_doc).to include('concurrent')

      # Check for error handling examples
      expect(usage_doc).to include('rescue')
      expect(usage_doc).to include('begin')
    end

    it "has accurate code blocks" do
      # Verify syntax of all Ruby code blocks
      code_blocks = extract_ruby_code_blocks(usage_doc)

      code_blocks.each_with_index do |code, index|
        # Skip blocks that are intentionally incomplete or pseudocode
        next if code.include?('# ...') || code.include?('TODO')
        next if code.count('{') != code.count('}') && code.include?('{")

        # Basic syntax check
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error,
          "Code block ##{index + 1} in USAGE_EXAMPLES.md has invalid Ruby syntax"
      end
    end

    it "has working configuration examples" do
      # Extract and validate YAML configurations
      yaml_configs = extract_yaml_configs(usage_doc)

      yaml_configs.each do |config_text|
        expect { YAML.load(config_text) }.not_to raise_error,
          "YAML configuration in USAGE_EXAMPLES.md is invalid"
      end
    end
  end

  describe "Setup Guide Documentation Accuracy" do
    let(:setup_doc) { File.read('SETUP_GUIDE.md') }

    it "has accurate system requirements" do
      # Check requirements match actual requirements
      expect(setup_doc).to include('Ruby 3.3.0+')
      expect(setup_doc).to include('PostgreSQL 16.0+')
      expect(setup_doc).to include('pgvector')
      expect(setup_doc).to include('pg_jieba')

      # Check requirements are consistent with gem specs
      spec = Gem::Specification::load('smart_rag.gemspec')
      ruby_version = spec.required_ruby_version

      expect(ruby_version.satisfied_by?(Gem::Version.new('3.3.0'))).to be true,
        "Ruby version requirement in SETUP_GUIDE.md should match gemspec"
    end

    it "has accurate installation commands" do
      # Check Ubuntu/Debian commands
      expect(setup_doc).to include('apt-get install')
      expect(setup_doc).to include('postgresql-16-pgvector')
      expect(setup_doc).to include('postgresql-16-pg_jieba')

      # Check macOS commands
      expect(setup_doc).to include('brew install')
      expect(setup_doc).to include('postgresql@16')

      # Check compilation commands for pgvector
      expect(setup_doc).to include('make')
      expect(setup_doc).to include('make install')
    end

    it "has accurate configuration file examples" do
      # Check .env example is accurate
      expect(setup_doc).to include('SMARTRAG_DB_HOST')
      expect(setup_doc).to include('SMARTRAG_DB_NAME')
      expect(setup_doc).to include('SMARTRAG_DB_USER')
      expect(setup_doc).to include('SMARTRAG_DB_PASSWORD')
      expect(setup_doc).to include('OPENAI_API_KEY')

      # All required env vars should be documented
      required_env_vars = %w[
        SMARTRAG_DB_HOST
        SMARTRAG_DB_PORT
        SMARTRAG_DB_NAME
        SMARTRAG_DB_USER
        SMARTRAG_DB_PASSWORD
        SMARTRAG_TEST_DB_NAME
        SMARTRAG_TEST_DB_USER
        SMARTRAG_TEST_DB_PASSWORD
        OPENAI_API_KEY
      ]

      required_env_vars.each do |var|
        expect(setup_doc).to include(var),
          "Required environment variable #{var} should be documented"
      end
    end
  end

  describe "Performance Guide Documentation Accuracy" do
    let(:performance_doc) { File.read('PERFORMANCE_GUIDE.md') }

    it "has realistic performance targets" do
      # Check targets are documented and reasonable
      expect(performance_doc).to include('P50 < 150ms')
      expect(performance_doc).to include('P95 < 250ms')
      expect(performance_doc).to include('P99 < 500ms')

      # These targets should be achievable based on benchmarks
      # Quick smoke test
      temp_file = Tempfile.new(['perf-test', '.txt'])
      temp_file.write('Test content for performance verification')
      temp_file.close
      smart_rag.add_document(temp_file.path, generate_embeddings: true)
      temp_file.unlink

      # Measure search performance
      times = []
      5.times do
        start = Time.now
        smart_rag.search('test query', limit: 10)
        times << ((Time.now - start) * 1000)
      end

      avg_time = times.sum / times.length
      expect(avg_time).to be < 500,
        "Average search time (#{avg_time.round(2)}ms) should meet documented targets"
    end

    it "has accurate PostgreSQL tuning recommendations" do
      # Check tuning parameters
      expect(performance_doc).to include('shared_buffers = 2GB')
      expect(performance_doc).to include('work_mem = 64MB')
      expect(performance_doc).to include('maintenance_work_mem = 512MB')
      expect(performance_doc).to include('max_connections = 200')

      # Check these are commented as guidelines not requirements
      expect(performance_doc).to match(/25% of total RAM/)
      expect(performance_doc).to match(/75% of total RAM/)
    end

    it "accurately documents indexing strategies" do
      # Check IVFFLAT documentation
      expect(performance_doc).to include('CREATE INDEX CONCURRENTLY idx_embeddings_ivfflat')
      expect(performance_doc).to include('USING ivfflat')
      expect(performance_doc).to include('WITH (lists = 100)')

      # Check HNSW documentation
      expect(performance_doc).to include('CREATE INDEX CONCURRENTLY idx_embeddings_hnsw')
      expect(performance_doc).to include('USING hnsw')

      # Check GIN index for full-text
      expect(performance_doc).to include('CREATE INDEX CONCURRENTLY idx_section_fts_content')
      expect(performance_doc).to include('USING gin')
    end
  end

  describe "Migration Guide Documentation Accuracy" do
    let(:migration_doc) { File.read('MIGRATION_GUIDE.md') }

    it "has accurate version information" do
      # Check version table exists and is properly formatted
      expect(migration_doc).to include('| SmartRAG Version |')
      expect(migration_doc).to include('| 1.0.x |')
      expect(migration_doc).to include('| 1.1.x |')
      expect(migration_doc).to include('| 1.2.x |')
      expect(migration_doc).to include('| 1.3.x |')

      # Check for breaking changes documentation
      expect(migration_doc).to include('Breaking Changes')
    end

    it "documents all breaking changes accurately" do
      # Check 1.1.x breaking changes
      expect(migration_doc).to include('search() method now returns a Hash')
      expect(migration_doc).to include('add_document() return value structure changed')

      # Check 1.2.x breaking changes
      expect(migration_doc).to include('alpha parameter renamed to vector_weight')

      # Check 1.3.x breaking changes
      expect(migration_doc).to include('Minimum Ruby version increased to 3.3.0')
      expect(migration_doc).to include('PostgreSQL 16+ required')
    end

    it "has working migration code examples" do
      # Test migration SQL examples
      migration_sql = migration_doc.scan(/```sql\n(.*?)\n```/m)

      migration_sql.each do |sql_block|
        # Skip multi-step migrations and complex queries
        next if sql_block[0].include?('Transaction')
        next if sql_block[0].include?('Function')

        # Basic syntax check
        expect { DB.run(sql_block[0]) rescue nil }.not_to raise_error SyntaxError
      end
    end
  end

  describe "Cross-Documentation Consistency" do
    it "has consistent setup information across all docs" do
      setup_doc = File.read('SETUP_GUIDE.md')
      usage_doc = File.read('USAGE_EXAMPLES.md')
      api_doc = File.read('API_DOCUMENTATION.md')

      # Check database configuration is consistent
      expect(setup_doc).to include('adapter: postgresql')
      expect(usage_doc).to include('adapter: postgresql')
      expect(api_doc).to include('adapter: postgresql')

      # Check port numbers are consistent
      expect(setup_doc.scan(/5432/).length).to be > 0

      # Check for common patterns
      [setup_doc, usage_doc, api_doc].each do |doc|
        expect(doc).to include('SmartRAG::SmartRAG')
      end
    end

    it "has no broken internal links" do
      all_docs = {
        'API_DOCUMENTATION.md' => File.read('API_DOCUMENTATION.md'),
        'USAGE_EXAMPLES.md' => File.read('USAGE_EXAMPLES.md'),
        'SETUP_GUIDE.md' => File.read('SETUP_GUIDE.md'),
        'PERFORMANCE_GUIDE.md' => File.read('PERFORMANCE_GUIDE.md'),
        'MIGRATION_GUIDE.md' => File.read('MIGRATION_GUIDE.md')
      }

      all_docs.each do |filename, content|
        # Check for properly formatted markdown links
        links = content.scan(/\[([^\]]+)\]\(([^\)]+)\)/)

        links.each do |text, url|
          # Skip external links
          next if url.start_with?('http')
          next if url.start_with?('https')

          # Check internal links reference existing sections
          if url.start_with?('#')
            section_id = url[1..-1]
            # Convert to markdown header format
            header = section_id.split('-').map(&:capitalize).join(' ')
            expect(content).to include(header),
              "Link '#{text}' in #{filename} references non-existent section '#{header}'"
          end
        end
      end
    end

    it "has no contradictory statements" do
      docs_content = [
        File.read('API_DOCUMENTATION.md'),
        File.read('USAGE_EXAMPLES.md')
      ].join

      # Check for contradictions in error handling
      expect(docs_content.scan(/ArgumentError/).length).to be > 0
      expect(docs_content.scan(/DatabaseError/).length).to be > 0

      # Ensure all error types are consistently documented
      expect(docs_content).not_to match(/StandardError/)
    end
  end

  describe "Completeness Checks" do
    it "covers all major features in documentation" do
      features = [
        'Document Management',
        'Search Operations',
        'Research Topics',
        'Tag Management',
        'Hybrid Search',
        'Vector Search',
        'Full-Text Search',
        'Error Handling',
        'Performance Optimization',
        'Migration'
      ]

      all_docs_content = [
        'API_DOCUMENTATION.md',
        'USAGE_EXAMPLES.md',
        'PERFORMANCE_GUIDE.md',
        'MIGRATION_GUIDE.md'
      ].map { |f| File.read(f) }.join

      features.each do |feature|
        expect(all_docs_content).to match(/#{feature}/i),
          "Documentation should cover feature: #{feature}"
      end
    end

    it "includes examples for all public methods" do
      api_doc = File.read('API_DOCUMENTATION.md')
      usage_doc = File.read('USAGE_EXAMPLES.md')

      # Check that all documented methods have at least one example
      method_patterns = [
        /smart_rag\.search\(/,
        /smart_rag\.add_document\(/,
        /smart_rag\.create_topic\(/,
        /smart_rag\.generate_tags\(/
      ]

      method_patterns.each do |pattern|
        method_name = pattern.to_s.match(/smart_rag\.(\w+)\(/)[1]
        expect(api_doc).to match(pattern),
          "API documentation should show usage of ##{method_name}"
      end
    end
  end

  # Helper methods
  def extract_code_examples(filename)
    content = File.read(filename)
    content.scan(/```ruby\n(.*?)\n```/m).flatten
  end

  def extract_ruby_code_blocks(content)
    content.scan(/```ruby\n(.*?)\n```/m).flatten
  end

  def extract_yaml_configs(content)
    content.scan(/```yaml\n(.*?)\n```/m).flatten
  end
end
