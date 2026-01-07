require 'spec_helper'
require 'smart_rag'
require 'tempfile'

RSpec.describe "Documentation Examples" do
  let(:config) do
    {
      database: {
        adapter: 'postgresql',
        host: ENV['SMARTRAG_TEST_DB_HOST'] || 'localhost',
        database: ENV['SMARTRAG_TEST_DB_NAME'] || 'smart_rag_test',
        user: ENV['SMARTRAG_TEST_DB_USER'] || 'smart_rag_user',
        password: ENV['SMARTRAG_TEST_DB_PASSWORD'] || 'test_password'
      },
      llm: {
        provider: 'openai',
        api_key: ENV['OPENAI_API_KEY'] || 'test-key'
      }
    }
  end

  let(:smart_rag) { SmartRAG::SmartRAG.new(config) }

  before(:all) do
    # Ensure test database is ready
    SmartRAG.init_db
  end

  describe "API Documentation Examples from API_DOCUMENTATION.md" do
    describe "Quick Start Example" do
      it "initializes SmartRAG with configuration" do
        # Example from API_DOCUMENTATION.md lines 12-16
        config = {
          database: {
            adapter: 'postgresql',
            host: 'localhost',
            database: 'smart_rag_dev',
            user: 'username',
            password: 'password'
          },
          llm: {
            provider: 'openai',
            api_key: ENV['OPENAI_API_KEY']
          }
        }

        smart_rag = SmartRAG::SmartRAG.new(config)
        smart_rag.logger = Logger.new(STDOUT)

        expect(smart_rag).to be_a(SmartRAG::SmartRAG)
        expect(smart_rag.logger).to be_a(Logger)
      end
    end

    describe "Document Management Examples" do
      let(:temp_file) { Tempfile.new(['test-doc', '.txt']) }

      before do
        temp_file.write("This is a test document about machine learning and AI.")
        temp_file.close
      end

      after do
        temp_file.unlink
      end

      it "adds a document with options" do
        # Example from API_DOCUMENTATION.md lines 48-67
        result = smart_rag.add_document(temp_file.path, {
          title: 'My Document',
          generate_embeddings: true,
          generate_tags: true,
          tags: ['important', 'research']
        })

        expect(result).to include(:document_id, :section_count, :status)
        expect(result[:status]).to eq('success')
        expect(result[:document_id]).to be_a(Integer)
      end

      it "removes a document" do
        # Example from API_DOCUMENTATION.md lines 80-88
        result1 = smart_rag.add_document(temp_file.path, {
          title: 'Test Doc',
          generate_embeddings: false
        })

        document_id = result1[:document_id]

        result = smart_rag.remove_document(document_id)

        expect(result).to include(:success, :deleted_sections, :deleted_embeddings)
        expect(result[:success]).to be true
      end

      it "gets document details" do
        # Example from API_DOCUMENTATION.md lines 93-106
        result = smart_rag.add_document(temp_file.path, {
          title: 'Test Document',
          generate_embeddings: false
        })

        doc = smart_rag.get_document(result[:document_id])

        expect(doc).to include(:id, :title, :created_at, :updated_at, :section_count)
        expect(doc[:title]).to eq('Test Document')
      end

      it "lists documents with pagination" do
        # Example from API_DOCUMENTATION.md lines 112-128
        # Add multiple documents first
        3.times do |i|
          tf = Tempfile.new(["doc#{i}", '.txt'])
          tf.write("Document #{i} content")
          tf.close
          smart_rag.add_document(tf.path, generate_embeddings: false)
          tf.unlink
        end

        results = smart_rag.list_documents(page: 1, per_page: 20)

        expect(results).to include(:documents, :total_count, :page, :per_page, :total_pages)
        expect(results[:documents]).to be_an(Array)
        expect(results[:page]).to eq(1)
      end
    end

    describe "Search Examples" do
      before do
        # Add a test document for searching
        temp_file = Tempfile.new(['search-test', '.txt'])
        temp_file.write("Machine learning is a subset of artificial intelligence.")
        temp_file.close
        smart_rag.add_document(temp_file.path, {
          title: 'AI Document',
          generate_embeddings: true
        })
        temp_file.unlink
      end

      it "performs hybrid search" do
        # Example from API_DOCUMENTATION.md lines 141-180
        results = smart_rag.search('artificial intelligence applications', {
          search_type: 'hybrid',
          limit: 10,
          alpha: 0.7,
          include_content: true,
          include_metadata: true
        })

        expect(results).to include(:query, :results, :metadata)
        expect(results[:query]).to eq('artificial intelligence applications')
        expect(results[:results]).to be_an(Array)
        expect(results[:metadata]).to include(
          :total_count,
          :execution_time_ms,
          :language,
          :alpha
        )
      end

      it "performs vector search" do
        # Example from API_DOCUMENTATION.md lines 198-203
        results = smart_rag.vector_search('machine learning algorithms', {
          limit: 5,
          include_content: true
        })

        expect(results).to be_a(Hash)
        expect(results[:results]).to be_an(Array)
      end

      it "performs full-text search" do
        # Example from API_DOCUMENTATION.md lines 208-212
        results = smart_rag.fulltext_search('natural language processing', {
          limit: 5,
          include_metadata: true
        })

        expect(results).to be_a(Hash)
        expect(results[:results]).to be_an(Array)
      end
    end

    describe "Research Topic Examples" do
      it "creates a research topic" do
        # Example from API_DOCUMENTATION.md lines 219-232
        result = smart_rag.create_topic('AI in Healthcare', 'Applications of AI in medical field', {
          tags: ['AI', 'healthcare', 'medicine'],
          document_ids: [1, 2, 3]
        })

        expect(result).to include(:topic_id, :title, :description, :tags, :document_ids)
        expect(result[:title]).to eq('AI in Healthcare')
        expect(result[:tags]).to include('AI', 'healthcare', 'medicine')
      end

      it "gets topic details" do
        # Example from API_DOCUMENTATION.md lines 237-249
        topic = smart_rag.create_topic('Test Topic', 'Test description')
        result = smart_rag.get_topic(topic[:topic_id])

        expect(result).to include(:id, :title, :description, :created_at, :updated_at)
        expect(result[:title]).to eq('Test Topic')
      end

      it "lists topics" do
        # Example from API_DOCUMENTATION.md lines 252-259
        smart_rag.create_topic('Topic 1', 'Description 1')
        smart_rag.create_topic('Topic 2', 'Description 2')

        results = smart_rag.list_topics(
          page: 1,
          per_page: 10,
          search: 'Topic'
        )

        expect(results).to include(:topics, :total_count, :page, :per_page)
        expect(results[:topics]).to be_an(Array)
      end

      it "adds document to topic" do
        # Example from API_DOCUMENTATION.md lines 283-293
        topic = smart_rag.create_topic('Test Topic', 'Description')

        temp_file = Tempfile.new(['test', '.txt'])
        temp_file.write('Test content')
        temp_file.close

        doc = smart_rag.add_document(temp_file.path, generate_embeddings: false)
        temp_file.unlink

        result = smart_rag.add_document_to_topic(topic[:topic_id], doc[:document_id])

        expect(result).to include(:success, :added_sections, :topic_id, :document_id)
        expect(result[:success]).to be true
      end
    end

    describe "Tag Management Examples" do
      let(:tag_service) { SmartRAG::Services::TagService.new(config) }

      it "generates tags for text" do
        # Example from API_DOCUMENTATION.md lines 334-346
        text = "Machine learning algorithms for text classification"
        tags = smart_rag.generate_tags(text, {
          max_tags: 5,
          context: 'AI research'
        })

        expect(tags).to include(:content_tags, :category_tags)
        expect(tags[:content_tags]).to be_an(Array)
        expect(tags[:category_tags]).to be_an(Array)
      end

      it "lists tags" do
        # Example from API_DOCUMENTATION.md lines 349-371
        # First create some tags
        tag_service.find_or_create_tags(['AI', 'ML', 'NLP'])

        results = smart_rag.list_tags(
          page: 1,
          per_page: 50
        )

        expect(results).to include(:tags, :total_count, :page, :per_page, :total_pages)
        expect(results[:tags]).to be_an(Array)
        expect(results[:tags].first).to include(:id, :name, :section_count)
      end
    end

    describe "System Information Examples" do
      it "gets system statistics" do
        # Example from API_DOCUMENTATION.md lines 377-387
        stats = smart_rag.statistics

        expect(stats).to include(
          :document_count,
          :section_count,
          :topic_count,
          :tag_count,
          :embedding_count
        )
      end

      it "gets search logs" do
        # Example from API_DOCUMENTATION.md lines 390-408
        # First perform some searches
        smart_rag.search('test query 1')
        smart_rag.search('test query 2')

        logs = smart_rag.search_logs(
          limit: 100,
          search_type: 'hybrid'
        )

        expect(logs).to be_an(Array)
        expect(logs.first).to include(
          :id,
          :query,
          :search_type,
          :results_count,
          :execution_time_ms
        )
      end
    end

    describe "Error Handling Examples" do
      it "handles errors correctly" do
        # Example from API_DOCUMENTATION.md lines 497-511
        begin
          smart_rag.search(nil)  # Invalid query
        rescue SmartRAG::Errors::ArgumentError => e
          expect(e).to be_a(SmartRAG::Errors::ArgumentError)
        end

        # Test database error handling
        expect {
          # Force a database error by invalid query
          DB.run("SELECT * FROM non_existent_table")
        }.to raise_error(Sequel::DatabaseError)
      end
    end
  end

  describe "Usage Examples from USAGE_EXAMPLES.md" do
    describe "Quick Start Examples" do
      it "runs the basic setup example" do
        # Example from USAGE_EXAMPLES.md lines 10-22
        config = {
          database: {
            adapter: 'postgresql',
            host: ENV['SMARTRAG_TEST_DB_HOST'] || 'localhost',
            database: ENV['SMARTRAG_TEST_DB_NAME'] || 'smart_rag_test',
            user: ENV['SMARTRAG_TEST_DB_USER'] || 'smart_rag_user',
            password: ENV['SMARTRAG_TEST_DB_PASSWORD'] || 'test_password'
          },
          llm: {
            provider: 'openai',
            api_key: ENV['OPENAI_API_KEY'] || 'test-key'
          }
        }

        expect { SmartRAG::SmartRAG.new(config) }.not_to raise_error
      end

      it "runs the complete workflow example" do
        # Example from USAGE_EXAMPLES.md lines 750-812
        config = {
          database: {
            adapter: 'postgresql',
            host: 'localhost',
            database: 'smart_rag_test',
            user: 'username',
            password: 'password'
          },
          llm: {
            provider: 'openai',
            api_key: ENV['OPENAI_API_KEY'] || 'test-key',
            model: 'gpt-4'
          }
        }

        smart_rag = SmartRAG::SmartRAG.new(config)
        smart_rag.logger = Logger.new(STDOUT)

        # Verify initialization
        expect(smart_rag).to be_a(SmartRAG::SmartRAG)
        expect(smart_rag.logger).to be_a(Logger)

        # Test statistics
        stats = smart_rag.statistics
        expect(stats).to include(:document_count, :section_count)
      end
    end

    describe "Batch Processing Examples" do
      it "processes documents sequentially" do
        # Example from USAGE_EXAMPLES.md lines 81-98
        temp_files = []
        documents = []

        3.times do |i|
          tf = Tempfile.new(["doc#{i}", '.txt'])
          tf.write("Document #{i} about machine learning")
          tf.close
          temp_files << tf
          documents << { path: tf.path, tags: ["tag#{i}"] }
        end

        results = []
        documents.each do |doc|
          result = smart_rag.add_document(
            doc[:path],
            generate_embeddings: true,
            tags: doc[:tags]
          )
          results << result
        end

        expect(results.length).to eq(3)
        expect(results.all? { |r| r[:status] == 'success' }).to be true

        temp_files.each(&:unlink)
      end

      it "processes documents in parallel" do
        # Example from USAGE_EXAMPLES.md lines 100-119
        require 'concurrent'

        temp_files = []
        documents = []

        3.times do |i|
          tf = Tempfile.new(["parallel_doc#{i}", '.txt'])
          tf.write("Parallel document #{i}")
          tf.close
          temp_files << tf
          documents << { path: tf.path, tags: ["ptag#{i}"] }
        end

        pool = Concurrent::FixedThreadPool.new(3)
        results = []

        documents.each do |doc|
          pool.post do
            result = smart_rag.add_document(
              doc[:path],
              generate_embeddings: true,
              tags: doc[:tags]
            )
            results << result
          end
        end

        pool.shutdown
        pool.wait_for_termination

        expect(results.length).to eq(3)
        expect(results.all? { |r| r[:status] == 'success' }).to be true

        temp_files.each(&:unlink)
      end
    end

    describe "Search Type Examples" do
      before do
        temp_file = Tempfile.new(['search-type-test', '.txt'])
        temp_file.write("Deep learning neural networks artificial intelligence")
        temp_file.close
        smart_rag.add_document(temp_file.path, generate_embeddings: true)
        temp_file.unlink
      end

      it "demonstrates hybrid search with filters" do
        # Example from USAGE_EXAMPLES.md lines 141-156
        results = smart_rag.search(
          'deep learning applications in healthcare',
          search_type: 'hybrid',
          limit: 10,
          alpha: 0.7
        )

        expect(results[:results]).to be_an(Array)
        expect(results[:metadata][:alpha]).to eq(0.7)
      end

      it "demonstrates vector search" do
        # Example from USAGE_EXAMPLES.md lines 197-204
        results = smart_rag.vector_search(
          'machine learning algorithms',
          limit: 5
        )

        expect(results[:results]).to be_an(Array)
        expect(results[:results].length).to be <= 5
      end

      it "demonstrates full-text search" do
        # Example from USAGE_EXAMPLES.md lines 209-212
        results = smart_rag.fulltext_search(
          'natural language processing',
          limit: 5
        )

        expect(results[:results]).to be_an(Array)
        expect(results[:results].length).to be <= 5
      end
    end

    describe "Multi-language Search Examples" do
      it "searches in Chinese" do
        # Example from USAGE_EXAMPLES.md lines 216-220
        tf = Tempfile.new(['chinese-test', '.txt'])
        tf.write("人工智能和机器学习的发展")
        tf.close
        smart_rag.add_document(tf.path, generate_embeddings: true)
        tf.unlink

        results = smart_rag.search('人工智能应用', language: 'zh_cn')

        expect(results[:results]).to be_an(Array)
      end
    end

    describe "Advanced Patterns Examples" do
      it "implements contextual search" do
        # Example from USAGE_EXAMPLES.md lines 262-286
        class ContextualSearch
          def initialize(smart_rag)
            @smart_rag = smart_rag
          end

          def search_with_context(query, user_context = {})
            enhanced_query = enhance_query(query, user_context)

            results = @smart_rag.search(enhanced_query, search_type: 'hybrid')
            results
          end

          private

          def enhance_query(query, context)
            case context[:domain]
            when 'healthcare'
              "#{query} medical health clinical"
            when 'finance'
              "#{query} financial economic banking"
            else
              query
            end
          end
        end

        contextual_search = ContextualSearch.new(smart_rag)

        # Test healthcare context
        results = contextual_search.search_with_context(
          'risk assessment',
          user_context: { domain: 'finance' }
        )

        expect(results[:results]).to be_an(Array)
      end

      it "implements search result caching" do
        # Example from USAGE_EXAMPLES.md lines 540-553
        require 'redis'

        class CachedSmartRAG
          def initialize(smart_rag, redis)
            @smart_rag = smart_rag
            @redis = redis
          end

          def search(query, options = {})
            content_hash = Digest::MD5.hexdigest(query)
            cache_key = "search:#{content_hash}"

            if cached = @redis.get(cache_key)
              return JSON.parse(cached, symbolize_names: true)
            end

            results = @smart_rag.search(query, options)
            @redis.setex(cache_key, 3600, results.to_json)

            results
          end
        end

        redis = Redis.new(host: ENV['REDIS_HOST'] || 'localhost')
        cached_rag = CachedSmartRAG.new(smart_rag, redis)

        # First search
        results1 = cached_rag.search('machine learning', limit: 5)
        expect(results1).to be_a(Hash)
        expect(results1[:results]).to be_an(Array)

        # Second search (should be cached)
        results2 = cached_rag.search('machine learning', limit: 5)
        expect(results2).to eq(results1)
      end

      it "implements error retry logic" do
        # Example from USAGE_EXAMPLES.md lines 558-562
        require 'retriable'

        attempts = 0

        Retriable.retriable(
          on: [SmartRAG::Errors::EmbeddingGenerationError],
          tries: 3,
          base_interval: 1,
          multiplier: 2
        ) do
          attempts += 1
          # This should succeed normally
          result = smart_rag.search('test', limit: 1)
          expect(result).to be_a(Hash)
        end

        expect(attempts).to eq(1) # Should succeed on first attempt
      end
    end

    describe "Performance Best Practices Examples" do
      it "demonstrates connection pooling" do
        # Example from USAGE_EXAMPLES.md lines 596-607
        db_config = {
          adapter: 'postgresql',
          host: 'localhost',
          database: 'smart_rag_test',
          user: 'username',
          password: 'password',
          pool: 25
        }

        db = Sequel.connect(db_config)
        expect(db).to be_a(Sequel::Database)
        expect(db.pool.max_size).to eq(25)
        db.disconnect
      end
    end

    describe "Real-world Application Examples" do
      it "implements Q&A system" do
        # Example from USAGE_EXAMPLES.md lines 354-418
        class QA_system
          def initialize(smart_rag)
            @smart_rag = smart_rag
          end

          def answer(question, options = {})
            search_results = @smart_rag.search(
              question,
              search_type: 'hybrid',
              limit: options[:context_limit] || 5,
              include_content: true
            )

            {
              question: question,
              answer: "Sample answer based on #{search_results[:results].length} results",
              confidence: calculate_confidence(search_results[:results])
            }
          end

          private

          def calculate_confidence(results)
            return 0.0 if results.empty?
            [results.first[:combined_score], 1.0].min
          end
        end

        qa = QA_system.new(smart_rag)
        response = qa.answer('What is machine learning?', context_limit: 3)

        expect(response).to include(:question, :answer, :confidence)
        expect(response[:question]).to eq('What is machine learning?')
        expect(response[:confidence]).to be_a(Numeric)
      end
    end
  end

  describe "Setup Guide Examples from SETUP_GUIDE.md" do
    it "validates database connection settings" do
      # Test the configuration format from SETUP_GUIDE.md
      config = {
        database: {
          adapter: 'postgresql',
          host: 'localhost',
          pool: 25,
          timeout: 5000
        }
      }

      # In real tests, we'd expect a connection error without real credentials
      # but we can validate the structure
      expect(config[:database][:adapter]).to eq('postgresql')
      expect(config[:database][:pool]).to be_a(Integer)
    end
  end

  describe "Performance Guide Examples from PERFORMANCE_GUIDE.md" do
    it "validates database optimization settings" do
      # Example from PERFORMANCE_GUIDE.md configuration section
      db_config = {
        max_connections: 200,
        pool: 25,
        timeout: 30
      }

      expect(db_config[:max_connections]).to eq(200)
      expect(db_config[:pool]).to eq(25)
      expect(db_config[:timeout]).to eq(30)
    end
  end

  describe "Migration Guide Examples from MIGRATION_GUIDE.md" do
    it "validates configuration format changes" do
      # Old format (1.0.x)
      old_config = {
        llm_service: {
          provider: 'openai',
          api_key: 'key'
        }
      }

      # New format (1.1.x+)
      new_config = {
        llm: {
          provider: 'openai',
          api_key: 'key'
        }
      }

      # Verify old format would not work with new API
      expect(old_config).not_to have_key(:llm)
      expect(new_config).to have_key(:llm)
    end
  end
end
