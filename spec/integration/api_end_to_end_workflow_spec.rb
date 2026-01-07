require 'spec_helper'
require 'smart_rag'
require 'fileutils'
require 'tempfile'

RSpec.describe 'SmartRAG API End-to-End Workflow' do
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
      },
      embedding: {
        dimensions: 1024
      }
    }
  end

  let(:smart_rag) { SmartRAG::SmartRAG.new(config) }

  before(:context) do
    # Ensure database is set up
    setup_test_database
  end

  before(:each) do
    # Clean up database before each test
    [:source_documents, :source_sections, :tags, :research_topics, :research_topic_sections,
     :research_topic_tags, :embeddings, :section_fts, :search_logs].each do |table|
      SmartRAG.db[table].delete if SmartRAG.db.table_exists?(table)
    end
  end

  describe 'Complete Knowledge Management Workflow' do
    it 'performs complete document lifecycle: add, search, organize, and delete' do
      # Step 1: Add documents to knowledge base
      expect(smart_rag.statistics[:document_count]).to eq(0)

      # Create test documents
      doc1_path = create_test_file('Machine learning is a subset of AI. Deep learning is a subset of ML.', 'ai_ml.txt')
      doc2_path = create_test_file('Natural language processing involves text analysis and understanding.', 'nlp.txt')
      doc3_path = create_test_file('Computer vision deals with image recognition and processing.', 'cv.txt')

      # Add documents to knowledge base
      doc1_info = smart_rag.add_document(doc1_path, {
        title: 'AI and Machine Learning',
        generate_tags: true,
        tags: ['AI', 'machine_learning']
      })

      expect(doc1_info[:document_id]).to be_a(Integer)
      expect(doc1_info[:section_count]).to be > 0

      doc2_info = smart_rag.add_document(doc2_path, {
        title: 'Natural Language Processing',
        tags: ['NLP', 'text_processing']
      })

      doc3_info = smart_rag.add_document(doc3_path, {
        title: 'Computer Vision',
        tags: ['computer_vision', 'image_processing']
      })

      # Verify documents were added
      stats = smart_rag.statistics
      expect(stats[:document_count]).to eq(3)
      expect(stats[:section_count]).to be >= 3

      # List documents
      document_list = smart_rag.list_documents(per_page: 10)
      expect(document_list[:documents].length).to eq(3)
      expect(document_list[:total_count]).to eq(3)

      # Get specific document
      document = smart_rag.get_document(doc1_info[:document_id])
      expect(document[:title]).to eq('AI and Machine Learning')

      # Step 2: Search across documents
      # Hybrid search
      hybrid_results = smart_rag.search('artificial intelligence', {
        search_type: 'hybrid',
        limit: 10
      })

      expect(hybrid_results[:query]).to eq('artificial intelligence')
      expect(hybrid_results[:results]).to be_an(Array)
      expect(hybrid_results[:metadata][:total_count]).to be >= 0

      # Vector search
      vector_results = smart_rag.vector_search('machine learning algorithms', {
        limit: 5,
        include_content: true
      })

      expect(vector_results[:query]).to eq('machine learning algorithms')
      expect(vector_results[:results]).to be_an(Array)

      # Full-text search
      fulltext_results = smart_rag.fulltext_search('natural language processing', {
        limit: 5,
        include_metadata: true
      })

      expect(fulltext_results[:query]).to eq('natural language processing')
      expect(fulltext_results[:results]).to be_an(Array)

      # Step 3: Create research topics and organize documents
      # Create topics
      ai_topic = smart_rag.create_topic(
        'Artificial Intelligence',
        'Research on AI technologies',
        tags: ['AI', 'technology'],
        document_ids: [doc1_info[:document_id]]
      )

      expect(ai_topic[:topic_id]).to be_a(Integer)
      expect(ai_topic[:title]).to eq('Artificial Intelligence')

      nlp_topic = smart_rag.create_topic(
        'Natural Language Processing',
        'NLP and text analysis research',
        tags: ['NLP', 'text_processing']
      )

      # Add documents to topics
      smart_rag.add_document_to_topic(ai_topic[:topic_id], doc3_info[:document_id])
      smart_rag.add_document_to_topic(nlp_topic[:topic_id], doc2_info[:document_id])

      # Get topic information
      ai_topic_info = smart_rag.get_topic(ai_topic[:topic_id])
      expect(ai_topic_info[:document_count]).to eq(2) # AI and Computer Vision docs
      expect(ai_topic_info[:tags]).to include('AI', 'technology')

      # List all topics
      topics_list = smart_rag.list_topics(per_page: 10)
      expect(topics_list[:topics].length).to eq(2)
      expect(topics_list[:total_count]).to eq(2)

      # Get topic recommendations
      recommendations = smart_rag.get_topic_recommendations(ai_topic[:topic_id], limit: 5)
      expect(recommendations[:topic_id]).to eq(ai_topic[:topic_id])
      expect(recommendations[:recommendations]).to be_an(Array)

      # Step 4: Tag management and content analysis
      # Generate tags for content
      content = 'Deep neural networks and reinforcement learning in modern AI systems.'
      generated_tags = smart_rag.generate_tags(content, max_tags: 5)

      expect(generated_tags[:content_tags]).to be_an(Array)
      expect(generated_tags[:category_tags]).to be_an(Array)

      # List all tags
      all_tags = smart_rag.list_tags(per_page: 50)
      expect(all_tags[:tags]).to be_an(Array)
      expect(all_tags[:total_count]).to be > 0

      # Step 5: Monitor and analyze usage
      # Get system statistics
      stats = smart_rag.statistics
      expect(stats[:document_count]).to eq(3)
      expect(stats[:topic_count]).to eq(2)
      expect(stats[:section_count]).to be >= 3
      expect(stats[:tag_count]).to be > 0

      # Check search logs
      search_logs = smart_rag.search_logs(limit: 10)
      expect(search_logs).to be_an(Array)
      expect(search_logs.length).to be > 0

      search_logs.each do |log|
        expect(log[:query]).to be_a(String)
        expect(log[:search_type]).to match(/hybrid|vector|fulltext/)
        expect(log[:execution_time_ms]).to be_a(Integer)
      end

      # Step 6: Update and clean up
      # Update topic
      updated_topic = smart_rag.update_topic(ai_topic[:topic_id], {
        title: 'AI and Machine Learning Research',
        description: 'Updated description'
      })

      expect(updated_topic[:title]).to eq('AI and Machine Learning Research')

      # Remove document from topic
      removal_result = smart_rag.remove_document_from_topic(ai_topic[:topic_id], doc3_info[:document_id])
      expect(removal_result[:success]).to be true
      expect(removal_result[:deleted_sections]).to be > 0

      # Verify removal
      ai_topic_info = smart_rag.get_topic(ai_topic[:topic_id])
      expect(ai_topic_info[:document_count]).to eq(1)

      # Step 7: Delete topic
      delete_result = smart_rag.delete_topic(nlp_topic[:topic_id])
      expect(delete_result[:success]).to be true

      topics_list = smart_rag.list_topics(per_page: 10)
      expect(topics_list[:total_count]).to eq(1)

      # Step 8: Remove documents
      smart_rag.remove_document(doc1_info[:document_id])
      smart_rag.remove_document(doc2_info[:document_id])
      smart_rag.remove_document(doc3_info[:document_id])

      final_stats = smart_rag.statistics
      expect(final_stats[:document_count]).to eq(0)
      expect(final_stats[:topic_count]).to eq(1) # Only AI topic remains

      # Clean up temporary files
      FileUtils.rm_rf(File.dirname(doc1_path))
    end

    it 'handles edge cases and error scenarios gracefully' do
      # Try to get non-existent document
      expect(smart_rag.get_document(99999)).to be_nil

      # Try to get non-existent topic
      expect(smart_rag.get_topic(99999)).to be_nil

      # Update non-existent topic
      expect(smart_rag.update_topic(99999, title: 'New Title')).to be_nil

      # Search with empty query (should handle gracefully)
      expect {
        smart_rag.search('')
      }.to raise_error(ArgumentError)

      # Remove non-existent document
      result = smart_rag.remove_document(99999)
      expect(result[:success]).to be false

      # Create topic and delete it twice
      topic = smart_rag.create_topic('Temporary Topic')
      smart_rag.delete_topic(topic[:topic_id])

      # Try to delete again
      result = smart_rag.delete_topic(topic[:topic_id])
      expect(result[:success]).to be false
    end
  end

  describe 'Search Quality and Performance' do
    before do
      # Create diverse test documents
      topics = ['Machine Learning', 'Deep Learning', 'Neural Networks', 'Data Science', 'AI Ethics']
      content_templates = [
        '%s is a field of artificial intelligence that focuses on pattern recognition.',
        'The applications of %s include image recognition, NLP, and predictive analytics.',
        'Recent advances in %s have enabled breakthroughs in various domains.'
      ]

      topics.each_with_index do |topic, i|
        content = content_templates.map { |template| template % topic }.join(' ')
        path = create_test_file(content, "#{topic.downcase.gsub(' ', '_')}.txt")

        smart_rag.add_document(path, {
          title: topic,
          tags: topic.split + ['AI', 'technology']
        })
      end
    end

    it 'performs searches with good relevance' do
      # Test hybrid search
      results = smart_rag.search('machine learning for image recognition', {
        search_type: 'hybrid',
        limit: 10,
        include_metadata: true
      })

      expect(results[:results].length).to be > 0
      expect(results[:metadata][:total_count]).to be > 0

      # Check that results contain relevant content
      if results[:results].any?
        first_result = results[:results].first
        expect(first_result[:section_id]).to be_a(Integer)
      end

      # Test that different search types return results
      vector_results = smart_rag.vector_search('deep neural networks', limit: 5)
      expect(vector_results[:results]).to be_an(Array)

      fulltext_results = smart_rag.fulltext_search('artificial intelligence ethics', limit: 5)
      expect(fulltext_results[:results]).to be_an(Array)
    end

    it 'handles pagination correctly' do
      # Get first page
      page1 = smart_rag.list_documents(per_page: 2, page: 1)
      expect(page1[:documents].length).to eq(2)
      expect(page1[:page]).to eq(1)

      # Get second page
      page2 = smart_rag.list_documents(per_page: 2, page: 2)
      expect(page2[:documents].length).to eq(2)
      expect(page2[:page]).to eq(2)

      # Pages should have different documents
      page1_ids = page1[:documents].map { |d| d[:id] }
      page2_ids = page2[:documents].map { |d| d[:id] }
      expect(page1_ids & page2_ids).to be_empty # No overlap
    end

    it 'measures search performance' do
      # Record search execution time
      start_time = Time.now
      results = smart_rag.search('artificial intelligence applications', limit: 20)
      end_time = Time.now

      execution_time = (end_time - start_time) * 1000 # Convert to milliseconds

      # Should return results quickly (adjust threshold based on environment)
      expect(execution_time).to be < 5000 # 5 seconds

      # Log execution time for monitoring
      puts "Search execution time: #{execution_time.round(2)}ms"
      puts "Results returned: #{results[:results].length}"
    end
  end

  describe 'Concurrent Operations' do
    it 'handles multiple concurrent searches' do
      queries = [
        'machine learning',
        'deep learning',
        'neural networks',
        'data science',
        'artificial intelligence'
      ]

      # Perform concurrent searches using threads
      threads = queries.map do |query|
        Thread.new do
          smart_rag.search(query, limit: 10)
        end
      end

      # Wait for all threads to complete
      results = threads.map(&:value)

      # All searches should complete successfully
      expect(results.length).to eq(5)
      results.each do |result|
        expect(result[:results]).to be_an(Array)
      end
    end

    it 'handles concurrent document operations' do
      # Create multiple documents concurrently
      threads = 3.times.map do |i|
        Thread.new do
          content = "Document #{i} content about AI and ML."
          path = create_test_file(content, "concurrent_doc_#{i}.txt")

          smart_rag.add_document(path, {
            title: "Concurrent Doc #{i}",
            tags: ['AI', 'test']
          })
        end
      end

      results = threads.map(&:value)
      expect(results.length).to eq(3)
      results.each do |result|
        expect(result[:document_id]).to be_a(Integer)
      end

      # Verify all documents were added
      stats = smart_rag.statistics
      expect(stats[:document_count]).to eq(3)
    end
  end

  private

  def setup_test_database
    # Ensure tables exist - this would normally be handled by migrations
    # For testing, we ensure the connection is available
    SmartRAG::Models.db
  end

  def create_test_file(content, filename)
    dir = Dir.mktmpdir('smart_rag_test')
    path = File.join(dir, filename)
    File.write(path, content)
    path
  end

  def cleanup_test_files
    FileUtils.rm_rf(Dir.glob('/tmp/smart_rag_test*'))
  end
end
