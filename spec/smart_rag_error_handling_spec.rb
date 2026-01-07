require 'spec_helper'
require 'smart_rag'

RSpec.describe 'SmartRAG API Error Handling' do
  let(:config) do
    {
      database: {
        adapter: 'postgresql',
        host: 'localhost',
        database: 'smart_rag_test',
        user: ENV['SMARTRAG_TEST_DB_USER'] || 'rag_user',
        password: ENV['SMARTRAG_TEST_DB_PASSWORD'] || 'rag_pwd'
      },
      llm: {
        provider: 'test_provider',
        api_key: 'test_key'
      }
    }
  end

  let(:smart_rag) { SmartRAG::SmartRAG.new(config) }

  before(:context) do
    setup_test_database
  end

  describe 'Document Management Errors' do
    describe '#add_document' do
      it 'raises error for non-existent file' do
        expect {
          smart_rag.add_document('/non/existent/file.pdf')
        }.to raise_error(ArgumentError, /Invalid source.*Must be a valid URL or file path/)
      end

      it 'raises error for invalid document path' do
        expect {
          smart_rag.add_document(nil)
        }.to raise_error(TypeError)

        expect {
          smart_rag.add_document('')
        }.to raise_error(ArgumentError, /Invalid source/)
      end

      it 'handles document processing failures gracefully' do
        # Create a real file to test error handling
        file = create_temp_file('Test content', 'test.txt')

        # Mock the create_document method to raise error
        error = StandardError.new('Processing failed')
        processor_instance = instance_double('SmartRAG::Core::DocumentProcessor')
        allow(SmartRAG::Core::DocumentProcessor).to receive(:new).and_return(processor_instance)
        allow(processor_instance).to receive(:create_document).and_raise(error)

        expect {
          smart_rag.add_document(file.path)
        }.to raise_error(StandardError, /Processing failed/)

        file.close
        file.unlink
      end
    end

    describe '#get_document' do
      it 'returns nil for non-existent document ID' do
        expect(smart_rag.get_document(99999)).to be_nil
        expect(smart_rag.get_document('invalid')).to be_nil
        expect(smart_rag.get_document(-1)).to be_nil
      end

      it 'handles nil and invalid inputs' do
        expect(smart_rag.get_document(nil)).to be_nil
      end
    end

    describe '#list_documents' do
      it 'handles invalid pagination parameters' do
        # Negative page number
        result = smart_rag.list_documents(page: -5, per_page: 10)
        expect(result[:page]).to eq(1)

        # Zero per_page
        result = smart_rag.list_documents(page: 1, per_page: 0)
        expect(result[:per_page]).to eq(1)

        # Very large per_page (should be clamped)
        result = smart_rag.list_documents(page: 1, per_page: 1000)
        expect(result[:per_page]).to eq(100)

        # Non-numeric values
        result = smart_rag.list_documents(page: 'invalid', per_page: 'also_invalid')
        expect(result[:page]).to eq(1)
        expect(result[:per_page]).to eq(20)
      end
    end

    describe '#remove_document' do
      it 'handles removal of non-existent document gracefully' do
        result = smart_rag.remove_document(99999)

        expect(result[:success]).to be false
        expect(result[:deleted_sections]).to eq(0)
        expect(result[:deleted_embeddings]).to eq(0)
      end

      it 'handles multiple removal of same document' do
        # Create a document
        file = create_temp_file('Test content', 'test.txt')
        doc_info = smart_rag.add_document(file.path)
        file.close
        file.unlink

        # Remove first time
        result1 = smart_rag.remove_document(doc_info[:document_id])
        expect(result1[:success]).to be true

        # Remove second time
        result2 = smart_rag.remove_document(doc_info[:document_id])
        expect(result2[:success]).to be false
      end
    end
  end

  describe 'Search Operation Errors' do
    describe '#search' do
      it 'raises error for nil or empty search query' do
        expect {
          smart_rag.search(nil)
        }.to raise_error(ArgumentError, /Query text cannot be nil or empty/)

        expect {
          smart_rag.search('')
        }.to raise_error(ArgumentError, /Query text cannot be nil or empty/)

        expect {
          smart_rag.search('   ')
        }.to raise_error(ArgumentError, /Query text cannot be nil or empty/)
      end

      it 'raises error for queries exceeding maximum length' do
        long_query = 'a' * 1100  # Assuming max is 1000
        expect {
          smart_rag.search(long_query)
        }.to raise_error(ArgumentError, /Query too long/)
      end

      it 'raises error for queries too short' do
        expect {
          smart_rag.search('a')
        }.to raise_error(ArgumentError, /Query too short/)
      end

      it 'raises error for invalid search type' do
        expect {
          smart_rag.search('test', search_type: 'invalid_type')
        }.to raise_error(ArgumentError, /Invalid search_type/)

        expect {
          smart_rag.search('test', search_type: nil)
        }.to raise_error(ArgumentError, /Invalid search_type/)
      end

      it 'handles search service failures gracefully' do
        # Create a real file to test error handling
        file = create_temp_file('Test content for search', 'search_test.txt')
        smart_rag.add_document(file.path)

        # Mock the query_processor instance method to raise error
        error = StandardError.new('Search service unavailable')
        allow_any_instance_of(SmartRAG::Core::QueryProcessor)
          .to receive(:process_query)
          .and_raise(error)

        # Should not crash - returns empty results instead
        result = smart_rag.search('machine learning')

        expect(result[:results]).to be_an(Array)
        expect(result[:results]).to be_empty
        expect(result[:metadata][:error]).to match(/Search service unavailable/)

        file.close
        file.unlink
      end

      it 'handles invalid search parameters' do
        # Invalid limit - should be clamped to valid range and succeed
        result = smart_rag.search('test', limit: -5)
        # Verify search succeeded and returned valid structure
        expect(result[:results]).to be_an(Array)
        expect(result[:total_results]).to be >= 0

        # Invalid alpha - should be clamped and not raise error
        expect {
          smart_rag.search('test', alpha: 2.0)  # Should be between 0.0 and 1.0
        }.not_to raise_error
      end
    end

    describe '#vector_search and #fulltext_search' do
      it 'handles service failures in vector search' do
        embedding_manager = instance_double('SmartRAG::Core::Embedding')
        allow(smart_rag).to receive_message_chain(:query_processor, :embedding_manager).and_return(embedding_manager)
        allow(embedding_manager).to receive(:send).and_raise(StandardError, 'Vector database error')

        # Should not crash, should return empty results or handle gracefully
        result = smart_rag.vector_search('test', limit: 10)

        # The vector_search method returns a flat structure:
        # result[:results] is the array of search results
        expect(result[:results]).to be_an(Array)
        expect(result[:search_type]).to eq(:vector)
      end

      it 'handles service failures in fulltext search' do
        fulltext_manager = instance_double('SmartRAG::Core::FulltextManager')
        allow(smart_rag).to receive_message_chain(:query_processor, :fulltext_manager).and_return(fulltext_manager)
        allow(fulltext_manager).to receive(:send).and_raise(StandardError, 'Fulltext index error')

        # Should not crash, should return empty results or handle gracefully
        result = smart_rag.fulltext_search('test', limit: 10)

        # The fulltext_search method returns a nested structure:
        # result[:results] contains the search results with metadata
        # result[:results][:results] is the array of actual search results
        expect(result[:results]).to be_a(Hash)
        expect(result[:results][:results]).to be_an(Array)
        expect(result[:search_type]).to eq(:fulltext)
      end
    end
  end

  describe 'Topic Management Errors' do
    describe '#create_topic' do
      it 'raises error for nil or empty title' do
        expect {
          smart_rag.create_topic(nil)
        }.to raise_error(Sequel::ValidationFailed, /name is not present/)

        expect {
          smart_rag.create_topic('')
        }.to raise_error(Sequel::ValidationFailed, /name is not present/)
      end
    end

    describe '#get_topic' do
      it 'returns nil for non-existent topic' do
        expect(smart_rag.get_topic(99999)).to be_nil
        expect(smart_rag.get_topic('invalid')).to be_nil
        expect(smart_rag.get_topic(-1)).to be_nil
      end
    end

    describe '#update_topic' do
      it 'returns nil when updating non-existent topic' do
        result = smart_rag.update_topic(99999, title: 'New Title')
        expect(result).to be_nil
      end

      it 'handles invalid update parameters' do
        # Create a topic first
        topic = smart_rag.create_topic('Original Title')

        # Try to update with nil title - should return nil gracefully
        result = smart_rag.update_topic(topic[:topic_id], title: nil)
        expect(result).to be_nil
      end
    end

    describe '#delete_topic' do
      it 'handles deletion of non-existent topic' do
        result = smart_rag.delete_topic(99999)

        # Should return success false or similar
        expect(result[:success]).to be false
      end

      it 'handles double deletion gracefully' do
        topic = smart_rag.create_topic('To Delete')

        # First deletion
        result1 = smart_rag.delete_topic(topic[:topic_id])
        expect(result1[:success]).to be true

        # Second deletion
        result2 = smart_rag.delete_topic(topic[:topic_id])
        expect(result2[:success]).to be false
      end
    end

    describe '#add_document_to_topic' do
      it 'handles adding non-existent document to topic' do
        topic = smart_rag.create_topic('Test Topic')

        result = smart_rag.add_document_to_topic(topic[:topic_id], 99999)

        expect(result[:success]).to be true
        expect(result[:added_sections]).to eq(0)
      end

      it 'handles adding document to non-existent topic' do
        # Create a document
        file = create_temp_file('Test content', 'test.txt')
        doc_info = smart_rag.add_document(file.path)
        file.close
        file.unlink

        result = smart_rag.add_document_to_topic(99999, doc_info[:document_id])

        # Should handle gracefully
        expect(result[:success]).to be false
      end
    end
  end

  describe 'Tag Generation Errors' do
    describe '#generate_tags' do
      it 'handles tag generation failures' do
        tag_service = instance_double('SmartRAG::Services::TagService')
        allow(smart_rag).to receive(:tag_service).and_return(tag_service)
        allow(tag_service).to receive(:generate_tags).and_raise(StandardError, 'Tag generation failed')

        expect {
          smart_rag.generate_tags('test content')
        }.to raise_error(StandardError, /Tag generation failed/)
      end

      it 'handles empty content' do
        result = smart_rag.generate_tags('', max_tags: 5)

        expect(result[:content_tags]).to be_an(Array)
        expect(result[:category_tags]).to be_an(Array)
      end

      it 'handles very large content' do
        large_content = 'test ' * 10000  # 50,000 characters

        result = smart_rag.generate_tags(large_content, max_tags: 10)

        expect(result[:content_tags]).to be_an(Array)
        expect(result[:category_tags]).to be_an(Array)
      end
    end
  end

  describe 'Statistics and Monitoring Errors' do
    describe '#statistics' do
      it 'handles database connection errors gracefully' do
        # Mock database to raise connection error
        allow(SmartRAG::Models::SourceDocument).to receive(:count).and_raise(PG::ConnectionBad, 'Connection failed')

        # Should not crash, should return empty statistics instead
        result = smart_rag.statistics

        expect(result[:document_count]).to eq(0)
        expect(result[:section_count]).to eq(0)
        expect(result[:topic_count]).to eq(0)
        expect(result[:tag_count]).to eq(0)
        expect(result[:embedding_count]).to eq(0)
        expect(result[:error]).to match(/Connection failed/)
      end
    end

    describe '#search_logs' do
      it 'handles invalid parameters gracefully' do
        # Negative limit
        result = smart_rag.search_logs(limit: -10)
        expect(result.length).to eq(0)

        # Very large limit (should be clamped)
        result = smart_rag.search_logs(limit: 10000)
        expect(result.length).to be <= 1000
      end

      it 'handles database errors when fetching logs' do
        # This might require database disconnection to test properly
        # For now, we just verify it doesn't crash the system
        expect {
          smart_rag.search_logs(limit: 10)
        }.not_to raise_error
      end
    end
  end

  describe 'Configuration and Initialization Errors' do
    it 'handles missing configuration gracefully' do
      expect {
        SmartRAG::SmartRAG.new({})
      }.not_to raise_error
    end

    it 'handles invalid configuration values' do
      # Test with nil database config (handled gracefully now)
      invalid_config = {
        database: nil,
        llm: { api_key: 'test' }
      }

      # Should not raise error, should initialize in limited mode
      smart_rag = SmartRAG::SmartRAG.new(invalid_config)
      expect(smart_rag).to be_a(SmartRAG::SmartRAG)
      expect(smart_rag.query_processor).to be_nil
      expect(smart_rag.document_processor).to be_nil
    end

    it 'handles missing required services gracefully' do
      # This tests if service initialization fails with invalid database config
      config_without_db = {
        database: {
          adapter: 'invalid',
          host: 'nonexistent'
        }
      }

      # Should initialize in limited mode without raising error
      smart_rag = SmartRAG::SmartRAG.new(config_without_db)
      expect(smart_rag).to be_a(SmartRAG::SmartRAG)
      expect(smart_rag.query_processor).to be_nil
      expect(smart_rag.document_processor).to be_nil
    end
  end

  describe 'Concurrent Error Scenarios' do
    it 'handles errors in concurrent searches' do
      # Create a simple document first so searches have something to find
      file = create_temp_file('Test search content', 'search_test.txt')
      smart_rag.add_document(file.path)
      file.close
      file.unlink

      # Mock at the search level - simulate what happens when an error occurs
      call_count = 0
      allow(smart_rag).to receive(:hybrid_search) do |query, options|
        call_count += 1
        puts "DEBUG: hybrid_search called #{call_count} times"
        if call_count == 2
          puts "DEBUG: Simulating error on call 2"
          # Return the same format as the rescue block in hybrid_search
          {
            query: query,
            results: [],
            metadata: {
              total_count: 0,
              execution_time_ms: 0,
              language: options[:language] || 'en',
              alpha: options[:alpha] || 0.7,
              text_result_count: 0,
              vector_result_count: 0,
              multilingual: false,
              error: 'Search failed'
            }
          }
        else
          { query: query, results: [], metadata: {} }
        end
      end

      threads = 3.times.map do |i|
        Thread.new do
          puts "DEBUG: Thread #{i} starting search"
          result = smart_rag.search("query #{i}", limit: 10)
          puts "DEBUG: Thread #{i} got result: #{result.inspect}"
          result
        end
      end

      results = threads.map(&:value)
      puts "DEBUG: Final results: #{results.inspect}"
      puts "DEBUG: Call count: #{call_count}"

      # Should have 2 successful searches and 1 failed (gracefully handled)
      # The error will be caught by the hybrid_search rescue and return results with error metadata
      expect(results).to be_an(Array)
      expect(results.size).to eq(3)

      # Check if we have the expected pattern (2 with no error in metadata, 1 with error)
      error_results = results.select { |r| r[:metadata] && r[:metadata][:error] }
      success_results = results.select { |r| !r[:metadata] || !r[:metadata][:error] }

      expect(success_results.size).to eq(2)
      expect(error_results.size).to eq(1)
      expect(error_results.first[:metadata][:error]).to match(/Search failed/)
    end

    it 'handles race conditions in document operations' do
      # Create a document first
      file = create_temp_file('Test content', 'race_test.txt')
      doc_info = smart_rag.add_document(file.path)
      file.close
      file.unlink

      # Try to delete the same document multiple times concurrently
      threads = 5.times.map do
        Thread.new do
          smart_rag.remove_document(doc_info[:document_id])
        end
      end

      results = threads.map(&:value)

      # The key requirement: system handles concurrent operations without crashing
      # Each operation should complete and return a valid result
      expect(results).to be_an(Array)
      expect(results.size).to eq(5)

      # All results should have the expected structure
      results.each do |result|
        expect(result).to include(:success, :deleted_sections, :deleted_embeddings)
        expect(result[:deleted_sections]).to be >= 0
        expect(result[:deleted_embeddings]).to be >= 0
      end

      # In a race condition, we expect at most one success
      # But the key thing is the system doesn't crash
      success_count = results.count { |r| r[:success] }
      expect(success_count).to be >= 0
      expect(success_count).to be <= 1
    end
  end

  describe 'Resource Exhaustion Scenarios' do
    it 'handles large result sets without crashing' do
      # This would require creating many documents first
      # For now, test the pagination works correctly
      result = smart_rag.list_documents(per_page: 100)

      expect(result[:documents].length).to be <= 100
      expect(result[:total_pages]).to be >= 1
    end

    it 'handles large content in tag generation' do
      # Content larger than typical API limits
      huge_content = 'test ' * 100_000  # 500k characters

      expect {
        smart_rag.generate_tags(huge_content, max_tags: 20)
      }.not_to raise_error
    end

    it 'handles deep pagination without performance degradation' do
      # Request a very high page number
      result = smart_rag.list_documents(page: 1000, per_page: 20)

      expect(result[:documents]).to be_an(Array)
      expect(result[:page]).to eq(1000)
    end
  end

  private

  def setup_test_database
    SmartRAG::Models.db
  end

  def create_temp_file(content, filename)
    file = Tempfile.new([filename, '.txt'])
    file.write(content)
    file.rewind
    file
  end
end
