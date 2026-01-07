require 'spec_helper'
require 'smart_rag'
require 'smart_rag/models/source_document'
require 'smart_rag/models/research_topic'
require 'smart_rag/core/document_processor'

# Helper to convert array to pgvector string format
def pgvector(vector_array)
  "[#{vector_array.join(',')}]"
end

RSpec.describe SmartRAG::SmartRAG do
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

  let(:smart_rag) { described_class.new(config) }

  before(:all) do
    # Create test database tables
    setup_test_database
  end

  describe 'initialization' do
    it 'creates instance with config' do
      expect(smart_rag).to be_a(described_class)
      expect(smart_rag.config).to be_a(Hash)
    end

    it 'initializes required services' do
      expect(smart_rag.query_processor).to be_a(SmartRAG::Core::QueryProcessor)
      expect(smart_rag.tag_service).to be_a(SmartRAG::Services::TagService)
      expect(smart_rag.document_processor).to be_a(SmartRAG::Core::DocumentProcessor)
    end
  end

  describe '#add_document' do
    let(:document_processor) { instance_double('SmartRAG::Core::DocumentProcessor') }
    let(:mock_document) { instance_double('SmartRAG::Models::SourceDocument', id: 1) }
    let(:mock_sections) { [instance_double('SmartRAG::Models::SourceSection')] }
    let(:temp_file) { Tempfile.new(['test', '.pdf']) }

    before do
      # Set the instance variable directly since the method accesses it directly
      smart_rag.instance_variable_set(:@document_processor, document_processor)
      allow(document_processor).to receive(:create_document).and_return({
        document: mock_document,
        sections: mock_sections
      })
    end

    after do
      temp_file.close
      temp_file.unlink
    end

    it 'adds a document and returns document info' do
      result = smart_rag.add_document(temp_file.path)

      expect(result[:document_id]).to eq(1)
      expect(result[:section_count]).to eq(1)
      expect(result[:status]).to eq('success')
    end

    it 'accepts processing options' do
      options = { title: 'Custom Title', generate_embeddings: false }
      smart_rag.add_document(temp_file.path, options)

      expect(document_processor).to have_received(:create_document)
        .with(temp_file.path, options)
    end
  end

  describe '#remove_document' do
    let!(:document) do
      SmartRAG::Models::SourceDocument.create(
        title: 'Test Document',
        created_at: Time.now
      )
    end

    let!(:section) do
      SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: 'Test content',
        section_title: 'Test Section',
        created_at: Time.now
      )
    end

    let!(:embedding) do
      SmartRAG::Models::Embedding.create(
        source_id: section.id,
        vector: pgvector(Array.new(1024) { rand }),
        created_at: Time.now
      )
    end

    it 'removes document and associated data' do
      result = smart_rag.remove_document(document.id)

      expect(result[:success]).to be true
      expect(result[:deleted_sections]).to eq(1)
      expect(result[:deleted_embeddings]).to eq(1)

      # Verify data is actually deleted
      expect(SmartRAG::Models::SourceDocument[document.id]).to be_nil
      expect(SmartRAG::Models::SourceSection[section.id]).to be_nil
      expect(SmartRAG::Models::Embedding[embedding.id]).to be_nil
    end

    it 'returns success false for non-existent document' do
      result = smart_rag.remove_document(99999)

      expect(result[:success]).to be false
      expect(result[:deleted_sections]).to eq(0)
    end
  end

  describe '#get_document' do
    let!(:document) do
      SmartRAG::Models::SourceDocument.create(
        title: 'Test Document',
        description: 'Test description',
        author: 'Test Author',
        created_at: Time.now,
        updated_at: Time.now,
        metadata: { 'key' => 'value' }.to_json
      )
    end

    let!(:section) do
      SmartRAG::Models::SourceSection.create(
        document_id: document.id,
        content: 'Test content',
        section_title: 'Test Section',
        created_at: Time.now
      )
    end

    it 'returns document information' do
      result = smart_rag.get_document(document.id)

      expect(result[:id]).to eq(document.id)
      expect(result[:title]).to eq('Test Document')
      expect(result[:description]).to eq('Test description')
      expect(result[:author]).to eq('Test Author')
      expect(result[:section_count]).to eq(1)
      expect(result[:metadata]).to eq({ 'key' => 'value' })
    end

    it 'returns nil for non-existent document' do
      result = smart_rag.get_document(99999)
      expect(result).to be_nil
    end
  end

  describe '#list_documents' do
    before do
      # Clean up existing documents to ensure test isolation
      SmartRAG::Models::Embedding.dataset.delete
      SmartRAG::Models::SourceSection.dataset.delete
      SmartRAG::Models::SourceDocument.dataset.delete
    end

    let!(:documents) do
      5.times.map do |i|
        doc = SmartRAG::Models::SourceDocument.create(
          title: "Test Document #{i + 1}",
          created_at: Time.now - (i * 3600)
        )

        # Add sections to each document
        2.times do |j|
          SmartRAG::Models::SourceSection.create(
            document_id: doc.id,
            content: "Section #{j + 1}",
            section_title: "Section #{j + 1}",
            created_at: Time.now
          )
        end

        doc
      end
    end

    it 'lists documents with pagination' do
      result = smart_rag.list_documents(per_page: 2, page: 1)

      expect(result[:documents].length).to eq(2)
      expect(result[:total_count]).to eq(5)
      expect(result[:page]).to eq(1)
      expect(result[:per_page]).to eq(2)
      expect(result[:total_pages]).to eq(3)

      # Check ordering (should be by created_at desc)
      expect(result[:documents].first[:id]).to eq(documents.first.id)
    end

    it 'filters documents by search term' do
      result = smart_rag.list_documents(search: 'Document 3')

      expect(result[:documents].length).to eq(1)
      expect(result[:documents].first[:title]).to eq('Test Document 3')
    end

    it 'uses default pagination values' do
      result = smart_rag.list_documents

      expect(result[:page]).to eq(1)
      expect(result[:per_page]).to eq(20)
      expect(result[:documents].length).to be <= 5
    end
  end

  describe '#search' do
    let(:query_processor) { instance_double('SmartRAG::Core::QueryProcessor') }

    before do
      allow(smart_rag).to receive(:query_processor).and_return(query_processor)
      allow(query_processor).to receive(:process_query).and_return({
        query: 'test query',
        results: [],
        metadata: {}
      })
    end

    it 'performs hybrid search by default' do
      smart_rag.search('test query')

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(search_type: :hybrid))
    end

    it 'supports vector search' do
      smart_rag.search('test query', search_type: 'vector')

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(search_type: :vector))
    end

    it 'supports fulltext search' do
      smart_rag.search('test query', search_type: 'fulltext')

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(search_type: :fulltext))
    end

    it 'raises error for invalid search type' do
      expect {
        smart_rag.search('test query', search_type: 'invalid')
      }.to raise_error(ArgumentError, /Invalid search_type/)
    end

    it 'passes options to query processor' do
      options = {
        limit: 50,
        alpha: 0.5,
        include_content: true,
        filters: { document_ids: [1, 2, 3] }
      }

      smart_rag.search('test query', options)

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(options))
    end
  end

  describe '#vector_search' do
    let(:query_processor) { instance_double('SmartRAG::Core::QueryProcessor') }

    before do
      allow(smart_rag).to receive(:query_processor).and_return(query_processor)
      allow(query_processor).to receive(:process_query).and_return({
        query: 'test query',
        results: [],
        metadata: {}
      })
    end

    it 'delegates to query processor with vector search type' do
      smart_rag.vector_search('test query', limit: 10)

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(search_type: :vector, limit: 10))
    end
  end

  describe '#fulltext_search' do
    let(:query_processor) { instance_double('SmartRAG::Core::QueryProcessor') }

    before do
      allow(smart_rag).to receive(:query_processor).and_return(query_processor)
      allow(query_processor).to receive(:process_query).and_return({
        query: 'test query',
        results: [],
        metadata: {}
      })
    end

    it 'delegates to query processor with fulltext search type' do
      smart_rag.fulltext_search('test query', limit: 10)

      expect(query_processor).to have_received(:process_query)
        .with('test query', hash_including(search_type: :fulltext, limit: 10))
    end
  end

  describe 'Research topic management' do
    describe '#create_topic' do
      it 'creates a topic with title and description' do
        result = smart_rag.create_topic('Test Topic', 'Test description')

        expect(result[:topic_id]).to be_a(Integer)
        expect(result[:title]).to eq('Test Topic')
        expect(result[:description]).to eq('Test description')

        # Verify in database
        topic = SmartRAG::Models::ResearchTopic[result[:topic_id]]
        expect(topic).not_to be_nil
        expect(topic.title).to eq('Test Topic')
      end

      it 'creates topic with tags' do
        result = smart_rag.create_topic('Tagged Topic', nil, tags: ['tag1', 'tag2'])

        topic = SmartRAG::Models::ResearchTopic[result[:topic_id]]
        expect(topic.tags.map(&:name)).to contain_exactly('tag1', 'tag2')
      end
    end

    describe '#get_topic' do
      let!(:topic) do
        smart_rag.create_topic('Test Topic', 'Description')
      end

      it 'returns topic information' do
        result = smart_rag.get_topic(topic[:topic_id])

        expect(result[:id]).to eq(topic[:topic_id])
        expect(result[:title]).to eq('Test Topic')
        expect(result[:description]).to eq('Description')
      end

      it 'returns nil for non-existent topic' do
        result = smart_rag.get_topic(99999)
        expect(result).to be_nil
      end
    end

    describe '#list_topics' do
      let!(:topics) do
        3.times.map do |i|
          smart_rag.create_topic("Topic #{i + 1}", "Description #{i + 1}")
        end
      end

      it 'lists topics with pagination' do
        result = smart_rag.list_topics(per_page: 2, page: 1)

        expect(result[:topics].length).to eq(2)
        expect(result[:total_count]).to eq(3)
        expect(result[:page]).to eq(1)
        expect(result[:per_page]).to eq(2)
      end

      it 'filters topics by search term' do
        result = smart_rag.list_topics(search: 'Topic 2')

        expect(result[:topics].length).to eq(1)
        expect(result[:topics].first[:title]).to eq('Topic 2')
      end
    end

    describe '#update_topic' do
      let!(:topic) do
        smart_rag.create_topic('Original Title', 'Original description', tags: ['tag1'])
      end

      it 'updates topic title and description' do
        result = smart_rag.update_topic(topic[:topic_id], title: 'Updated Title')

        expect(result[:title]).to eq('Updated Title')
        expect(result[:description]).to eq('Original description')

        topic_record = SmartRAG::Models::ResearchTopic[topic[:topic_id]]
        expect(topic_record.title).to eq('Updated Title')
      end

      it 'updates topic tags' do
        result = smart_rag.update_topic(topic[:topic_id], tags: ['new_tag1', 'new_tag2'])

        topic_record = SmartRAG::Models::ResearchTopic[topic[:topic_id]]
        expect(topic_record.tags.map(&:name)).to contain_exactly('new_tag1', 'new_tag2')
      end

      it 'returns nil for non-existent topic' do
        result = smart_rag.update_topic(99999, title: 'Updated')
        expect(result).to be_nil
      end
    end

    describe '#delete_topic' do
      let!(:topic) do
        smart_rag.create_topic('To Delete', 'Will be deleted')
      end

      it 'deletes topic and returns success' do
        result = smart_rag.delete_topic(topic[:topic_id])

        expect(result[:success]).to be true
        expect(result[:topic_id]).to eq(topic[:topic_id])

        # Verify deletion
        expect(SmartRAG::Models::ResearchTopic[topic[:topic_id]]).to be_nil
      end
    end

    describe '#add_document_to_topic' do
      let!(:document) do
        SmartRAG::Models::SourceDocument.create(
          title: 'Test Document',
          created_at: Time.now
        )
      end

      let!(:sections) do
        3.times.map do |i|
          SmartRAG::Models::SourceSection.create(
            document_id: document.id,
            content: "Content #{i + 1}",
            section_title: "Section #{i + 1}",
            created_at: Time.now
          )
        end
      end

      let!(:topic) do
        smart_rag.create_topic('Test Topic')
      end

      it 'adds document sections to topic' do
        result = smart_rag.add_document_to_topic(topic[:topic_id], document.id)

        expect(result[:success]).to be true
        expect(result[:added_sections]).to eq(3)
        expect(result[:topic_id]).to eq(topic[:topic_id])
        expect(result[:document_id]).to eq(document.id)

        # Verify associations
        topic_record = SmartRAG::Models::ResearchTopic[topic[:topic_id]]
        expect(topic_record.sections.count).to eq(3)
      end

      it 'only adds sections not already in topic' do
        # Add document first time
        smart_rag.add_document_to_topic(topic[:topic_id], document.id)

        # Add same document again
        result = smart_rag.add_document_to_topic(topic[:topic_id], document.id)

        expect(result[:added_sections]).to eq(0)

        # Verify associations
        topic_record = SmartRAG::Models::ResearchTopic[topic[:topic_id]]
        expect(topic_record.sections.count).to eq(3)
      end
    end

    describe '#remove_document_from_topic' do
      let!(:document) do
        SmartRAG::Models::SourceDocument.create(
          title: 'Test Document',
          created_at: Time.now
        )
      end

      let!(:sections) do
        2.times.map do |i|
          SmartRAG::Models::SourceSection.create(
            document_id: document.id,
            content: "Content #{i + 1}",
            section_title: "Section #{i + 1}",
            created_at: Time.now
          )
        end
      end

      let!(:topic) do
        smart_rag.create_topic('Test Topic')
      end

      before do
        smart_rag.add_document_to_topic(topic[:topic_id], document.id)
      end

      it 'removes document sections from topic' do
        result = smart_rag.remove_document_from_topic(topic[:topic_id], document.id)

        expect(result[:success]).to be true
        expect(result[:deleted_sections]).to eq(2)

        # Verify removal
        topic_record = SmartRAG::Models::ResearchTopic[topic[:topic_id]]
        expect(topic_record.sections.count).to eq(0)
      end
    end

    describe '#get_topic_recommendations' do
      let!(:topic1) { smart_rag.create_topic('Topic 1', nil, tags: ['AI', 'machine_learning']) }
      let!(:topic2) { smart_rag.create_topic('Topic 2', nil, tags: ['AI']) }

      let!(:document1) do
        doc = SmartRAG::Models::SourceDocument.create(title: 'Doc 1', created_at: Time.now)
        section = SmartRAG::Models::SourceSection.create(
          document_id: doc.id,
          content: 'ML content',
          section_title: 'ML Section',
          created_at: Time.now
        )

        # Add tags to section
        tag1 = SmartRAG::Models::Tag.find_or_create(name: 'AI')
        tag2 = SmartRAG::Models::Tag.find_or_create(name: 'machine_learning')
        SmartRAG::Models::SectionTag.create(section_id: section.id, tag_id: tag1.id)
        SmartRAG::Models::SectionTag.create(section_id: section.id, tag_id: tag2.id)

        doc
      end

      let!(:document2) do
        doc = SmartRAG::Models::SourceDocument.create(title: 'Doc 2', created_at: Time.now)
        section = SmartRAG::Models::SourceSection.create(
          document_id: doc.id,
          content: 'AI content',
          section_title: 'AI Section',
          created_at: Time.now
        )

        # Add tag to section
        tag = SmartRAG::Models::Tag.find_or_create(name: 'AI')
        SmartRAG::Models::SectionTag.create(section_id: section.id, tag_id: tag.id)

        doc
      end

      it 'returns recommendations based on matching tags' do
        result = smart_rag.get_topic_recommendations(topic2[:topic_id], limit: 10)

        expect(result[:topic_id]).to eq(topic2[:topic_id])
        # Should recommend documents with matching tags
        expect(result[:recommendations]).not_to be_empty
      end
    end
  end

  describe 'Tag management' do
    let(:tag_service) { instance_double('SmartRAG::Services::TagService') }

    before do
      allow(smart_rag).to receive(:tag_service).and_return(tag_service)
      allow(tag_service).to receive(:generate_tags).and_return({
        content_tags: ['tag1', 'tag2'],
        category_tags: ['category1']
      })
    end

    describe '#generate_tags' do
      it 'delegates to tag service' do
        result = smart_rag.generate_tags('test content', max_tags: 3, context: 'test context')

        expect(tag_service).to have_received(:generate_tags)
          .with('test content', 'test context', [:en], max_tags: 3)
        expect(result[:content_tags]).to eq(['tag1', 'tag2'])
      end
    end

    describe '#list_tags' do
      before do
        # Create a document first to avoid foreign key constraint
        document = SmartRAG::Models::SourceDocument.create(
          title: 'Test Document',
          created_at: Time.now
        )

        5.times do |i|
          tag = SmartRAG::Models::Tag.create(name: "Tag #{i + 1}")
          section = SmartRAG::Models::SourceSection.create(
            document_id: document.id,
            content: "Content #{i}",
            section_title: "Section #{i}",
            created_at: Time.now
          )
          SmartRAG::Models::SectionTag.create(section_id: section.id, tag_id: tag.id)
        end
      end

      it 'lists tags with pagination' do
        result = smart_rag.list_tags(per_page: 2, page: 1)

        expect(result[:tags].length).to eq(2)
        expect(result[:total_count]).to eq(5)
        expect(result[:page]).to eq(1)
        expect(result[:per_page]).to eq(2)
      end

      it 'includes tag information' do
        result = smart_rag.list_tags(per_page: 1)

        tag = result[:tags].first
        expect(tag[:name]).to be_a(String)
        expect(tag[:section_count]).to be >= 0
      end
    end
  end

  describe 'Statistics and monitoring' do
    describe '#statistics' do
      before do
        # Create some test data
        3.times do |i|
          doc = SmartRAG::Models::SourceDocument.create(
            title: "Doc #{i + 1}",
            created_at: Time.now
          )

          2.times do |j|
            section = SmartRAG::Models::SourceSection.create(
              document_id: doc.id,
              content: "Content #{j}",
              section_title: "Section #{j}",
              created_at: Time.now
            )

            SmartRAG::Models::Embedding.create(
              source_id: section.id,
              vector: pgvector(Array.new(1024) { rand }),
              created_at: Time.now
            )
          end
        end

        2.times do |i|
          tag = SmartRAG::Models::Tag.create(name: "Tag #{i + 1}")
          topic = SmartRAG::Models::ResearchTopic.create(
            title: "Topic #{i + 1}",
            created_at: Time.now
          )
        end
      end

      it 'returns correct statistics' do
        result = smart_rag.statistics

        expect(result[:document_count]).to eq(3)
        expect(result[:section_count]).to eq(6)
        expect(result[:embedding_count]).to eq(6)
        expect(result[:tag_count]).to eq(2)
        expect(result[:topic_count]).to eq(2)
      end
    end

    describe '#search_logs' do
      let!(:logs) do
        10.times.map do |i|
          SmartRAG::Models::SearchLog.create(
            query: "Query #{i + 1}",
            search_type: i.even? ? 'hybrid' : 'vector',
            results_count: rand(1..100),
            execution_time_ms: rand(50..500),
            created_at: Time.now - (i * 60),
            filters: i == 0 ? '{"error": "test error"}' : nil
          )
        end
      end

      it 'returns recent search logs' do
        result = smart_rag.search_logs(limit: 5)

        expect(result.length).to eq(5)
        expect(result.first[:query]).to eq('Query 1')
      end

      it 'filters by search type' do
        result = smart_rag.search_logs(search_type: 'hybrid')

        expect(result.all? { |log| log[:search_type] == 'hybrid' }).to be true
      end

      it 'includes error information when present' do
        result = smart_rag.search_logs(limit: 10)

        error_log = result.find { |log| log[:query] == 'Query 1' }
        expect(error_log[:error]).to eq('test error')
      end
    end
  end

  private

  def setup_test_database
    # Ensure database connection is established
    SmartRAG::Models.db
  end
end
