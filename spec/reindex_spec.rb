require 'unit_spec_helper'
require 'smart_rag'

RSpec.describe SmartRAG::SmartRAG do
  let(:smart_rag) do
    instance = described_class.allocate
    instance.instance_variable_set(:@logger, Logger.new(nil))
    instance
  end

  before do
    embedding_model = Class.new do
      def self.delete_by_section(_section_id); end
    end
    source_document_model = Class.new do
      def self.dataset
        @dataset ||= Class.new do
          def self.limit(_n) = self
          def self.all = []
        end
      end

      def self.all
        []
      end
    end

    stub_const('SmartRAG::Models::Embedding', embedding_model)
    stub_const('SmartRAG::Models::SourceDocument', source_document_model)
  end

  describe '#rebuild_fts' do
    it 'rebuilds fulltext index for sections and reports failures' do
      manager = instance_double('FulltextManager')
      service = instance_double('FulltextSearchService', fulltext_manager: manager)
      qp = instance_double('QueryProcessor', fulltext_search_service: service)
      allow(smart_rag).to receive(:query_processor).and_return(qp)

      doc = instance_double('SourceDocument', language: 'en')
      s1 = instance_double('SourceSection', id: 1, section_title: 'A', content: 'aaa', document: doc)
      s2 = instance_double('SourceSection', id: 2, section_title: 'B', content: 'bbb', document: doc)
      allow(smart_rag).to receive(:sections_scope).and_return([s1, s2])

      expect(manager).to receive(:update_fulltext_index).with(1, 'A', 'aaa', 'en').and_return(true)
      expect(manager).to receive(:update_fulltext_index).with(2, 'B', 'bbb', 'en').and_return(false)

      result = smart_rag.rebuild_fts
      expect(result[:success]).to be false
      expect(result[:indexed_sections]).to eq(1)
      expect(result[:failed_sections]).to eq(1)
      expect(result[:errors].first[:section_id]).to eq(2)
    end
  end

  describe '#rebuild_embeddings' do
    it 'rebuilds embeddings by deleting old ones then generating new ones' do
      embedding_service = instance_double('EmbeddingService')
      qp = instance_double('QueryProcessor', embedding_service: embedding_service)
      allow(smart_rag).to receive(:query_processor).and_return(qp)

      s1 = instance_double('SourceSection', id: 10)
      s2 = instance_double('SourceSection', id: 11)
      allow(smart_rag).to receive(:sections_scope).and_return([s1, s2])

      expect(SmartRAG::Models::Embedding).to receive(:delete_by_section).with(10)
      expect(SmartRAG::Models::Embedding).to receive(:delete_by_section).with(11)
      expect(embedding_service).to receive(:generate_for_section).with(s1)
      expect(embedding_service).to receive(:generate_for_section).with(s2).and_raise('embed fail')

      result = smart_rag.rebuild_embeddings
      expect(result[:success]).to be false
      expect(result[:rebuilt_embeddings]).to eq(1)
      expect(result[:failed_sections]).to eq(1)
      expect(result[:errors].first[:section_id]).to eq(11)
    end
  end

  describe '#reindex' do
    it 'combines rebuild_fts and rebuild_embeddings results' do
      allow(smart_rag).to receive(:rebuild_fts).and_return(success: true, indexed_sections: 2, failed_sections: 0)
      allow(smart_rag).to receive(:rebuild_embeddings).and_return(success: false, rebuilt_embeddings: 1, failed_sections: 1)

      result = smart_rag.reindex
      expect(result[:success]).to be false
      expect(result[:fts][:indexed_sections]).to eq(2)
      expect(result[:embeddings][:failed_sections]).to eq(1)
    end
  end

  describe '#dedupe_by_content_hash' do
    it 'removes duplicate documents sharing the same content hash' do
      d1 = instance_double('SourceDocument', id: 1, created_at: Time.utc(2026, 2, 18))
      d2 = instance_double('SourceDocument', id: 2, created_at: Time.utc(2026, 2, 19))
      d3 = instance_double('SourceDocument', id: 3, created_at: Time.utc(2026, 2, 19))

      allow(SmartRAG::Models::SourceDocument).to receive(:all).and_return([d1, d2, d3])
      allow(smart_rag).to receive(:document_content_hash).with(d1).and_return('hash-a')
      allow(smart_rag).to receive(:document_content_hash).with(d2).and_return('hash-a')
      allow(smart_rag).to receive(:document_content_hash).with(d3).and_return('hash-b')
      allow(smart_rag).to receive(:document_source_uri).with(d1).and_return('https://example.com/a')
      allow(smart_rag).to receive(:document_source_uri).with(d2).and_return('https://example.com/a')
      allow(smart_rag).to receive(:document_source_uri).with(d3).and_return('https://example.com/b')
      expect(smart_rag).to receive(:remove_document).with(2)

      result = smart_rag.dedupe_by_content_hash
      expect(result[:success]).to be true
      expect(result[:deduped_groups]).to eq(1)
      expect(result[:deleted_documents]).to eq(1)
    end
  end

  describe '#backfill_source_fields' do
    it 'fills missing source fields for documents' do
      doc = instance_double(
        'SourceDocument',
        id: 9,
        source_uri: nil,
        source_type: nil,
        content_hash: nil
      )
      allow(doc).to receive(:update)

      dataset = instance_double('Dataset')
      allow(dataset).to receive(:all).and_return([doc])
      allow(SmartRAG::Models::SourceDocument).to receive(:dataset).and_return(dataset)

      allow(smart_rag).to receive(:document_source_uri).with(doc).and_return('https://example.com/x')
      allow(smart_rag).to receive(:document_content_hash).with(doc).and_return('hash-x')

      result = smart_rag.backfill_source_fields

      expect(doc).to have_received(:update).with(
        hash_including(source_uri: 'https://example.com/x', source_type: 'url', content_hash: 'hash-x')
      )
      expect(result[:success]).to be true
      expect(result[:updated_documents]).to eq(1)
    end

    it 'supports dry_run without writing updates' do
      doc = instance_double(
        'SourceDocument',
        id: 10,
        source_uri: nil,
        source_type: nil,
        content_hash: nil
      )
      allow(doc).to receive(:update)

      dataset = instance_double('Dataset')
      allow(dataset).to receive(:all).and_return([doc])
      allow(SmartRAG::Models::SourceDocument).to receive(:dataset).and_return(dataset)

      allow(smart_rag).to receive(:document_source_uri).with(doc).and_return('file:///tmp/a.md')
      allow(smart_rag).to receive(:document_content_hash).with(doc).and_return('hash-y')

      result = smart_rag.backfill_source_fields(dry_run: true)
      expect(doc).not_to have_received(:update)
      expect(result[:dry_run]).to be true
      expect(result[:updated_documents]).to eq(1)
    end
  end

  describe '#prepare_release_indexes' do
    it 'runs all steps in non-dry mode' do
      allow(smart_rag).to receive(:backfill_source_fields).and_return(success: true, updated_documents: 2, skipped_documents: 0, errors: [])
      allow(smart_rag).to receive(:dedupe_by_content_hash).and_return(success: true, deduped_groups: 1, deleted_documents: 1)
      allow(smart_rag).to receive(:reindex).and_return(success: true)

      result = smart_rag.prepare_release_indexes(document_id: 5, dry_run: false)
      expect(result[:success]).to be true
      expect(result.dig(:dedupe, :deduped_groups)).to eq(1)
      expect(result.dig(:reindex, :success)).to be true
    end

    it 'skips destructive steps in dry_run mode' do
      allow(smart_rag).to receive(:backfill_source_fields).with(dry_run: true).and_return(success: true, updated_documents: 0, skipped_documents: 3, errors: [])
      expect(smart_rag).not_to receive(:dedupe_by_content_hash)
      expect(smart_rag).not_to receive(:reindex)

      result = smart_rag.prepare_release_indexes(dry_run: true)
      expect(result[:success]).to be true
      expect(result.dig(:dedupe, :dry_run)).to be true
      expect(result.dig(:reindex, :dry_run)).to be true
    end
  end
end
