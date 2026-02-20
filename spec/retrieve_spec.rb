require 'unit_spec_helper'
require 'smart_rag'

RSpec.describe SmartRAG::SmartRAG do
  let(:smart_rag) do
    instance = described_class.allocate
    instance.instance_variable_set(:@logger, Logger.new(nil))
    instance
  end

  describe '#retrieve' do
    it 'returns evidence pack with required top-level fields and signals' do
      allow(smart_rag).to receive(:search).and_return(
        {
          results: [
            {
              section: {
                id: 101,
                document_id: 42,
                content: 'SmartRAG retrieve plan example content',
                section_title: 'Retrieve Intro'
              },
              combined_score: 0.92,
              vector_score: 0.81,
              text_score: 0.76,
              rerank_score: 0.88
            }
          ]
        }
      )

      plan = {
        version: '0.1',
        request_id: 'req-001',
        purpose: 'qa',
        queries: [
          { text: 'retrieve plan', mode: 'hybrid', weight: 1.0 }
        ],
        budget: { top_k: 5 }
      }

      pack = smart_rag.retrieve(plan: plan)

      expect(pack[:version]).to eq('0.1')
      expect(pack[:request_id]).to eq('req-001')
      expect(pack[:plan_id]).not_to be_nil
      expect(pack[:generated_at]).not_to be_nil
      expect(pack[:evidences]).not_to be_empty
      expect(pack[:stats]).to include(:candidates, :returned, :took_ms)
      expect(pack[:explain]).to include(:fusion, :rerank, :ignored_fields)

      evidence = pack[:evidences].first
      expect(evidence[:id]).to eq('section:101')
      expect(evidence[:document_id]).to eq(42)
      expect(evidence[:section_id]).to eq(101)
      expect(evidence[:snippet]).to include('SmartRAG')
      expect(evidence[:signals]).to include(:vector_score, :fts_score, :rrf_score, :rerank_score)
      expect(evidence[:provenance]).to include(mode: 'hybrid', query_text: 'retrieve plan', query_index: 0)
    end

    it 'applies budget and diversity by document' do
      allow(smart_rag).to receive(:search).and_return(
        {
          results: [
            {
              section: { id: 1, document_id: 7, content: 'doc7-a' },
              combined_score: 0.95,
              vector_score: 0.8
            },
            {
              section: { id: 2, document_id: 7, content: 'doc7-b' },
              combined_score: 0.93,
              vector_score: 0.79
            },
            {
              section: { id: 3, document_id: 8, content: 'doc8-a' },
              combined_score: 0.90,
              vector_score: 0.75
            }
          ]
        }
      )

      pack = smart_rag.retrieve(
        plan: {
          version: '0.1',
          request_id: 'req-diversity',
          queries: [{ text: 'diversity query', mode: 'hybrid', weight: 1.0 }],
          budget: {
            top_k: 5,
            diversity: { by_document: 1, by_source: 2 }
          }
        }
      )

      expect(pack[:evidences].length).to eq(2)
      expect(pack[:evidences].map { |e| e[:document_id] }.uniq.length).to eq(2)
      expect(pack.dig(:explain, :ignored_fields).join(' ')).to include('diversity constraints partially applied')
    end

    it 'applies diversity by source' do
      allow(smart_rag).to receive(:search).and_return(
        {
          results: [
            {
              section: { id: 10, document_id: 100, content: 's1' },
              metadata: { source_uri: 'https://a.com/1', source_type: 'url' },
              combined_score: 0.99
            },
            {
              section: { id: 11, document_id: 101, content: 's2' },
              metadata: { source_uri: 'https://a.com/1', source_type: 'url' },
              combined_score: 0.98
            },
            {
              section: { id: 12, document_id: 102, content: 's3' },
              metadata: { source_uri: 'https://b.com/2', source_type: 'url' },
              combined_score: 0.97
            }
          ]
        }
      )

      pack = smart_rag.retrieve(
        plan: {
          version: '0.1',
          request_id: 'req-source-diversity',
          queries: [{ text: 'source diversity', mode: 'hybrid', weight: 1.0 }],
          budget: {
            top_k: 5,
            diversity: { by_source: 1 }
          }
        }
      )

      uris = pack[:evidences].map { |e| e[:source_uri] }
      expect(uris.length).to eq(2)
      expect(uris.uniq.length).to eq(2)
    end

    it 'applies output controls for snippet and raw payload' do
      long_text = 'x' * 120
      allow(smart_rag).to receive(:search).and_return(
        {
          results: [
            {
              section: { id: 66, document_id: 9, content: long_text, section_title: 'Long' },
              combined_score: 0.7
            }
          ]
        }
      )

      pack = smart_rag.retrieve(
        plan: {
          version: '0.1',
          request_id: 'req-output',
          queries: [{ text: 'long snippet', mode: 'hybrid', weight: 1.0 }],
          output: {
            include_snippets: true,
            include_raw: true,
            max_snippet_chars: 20
          }
        }
      )

      evidence = pack[:evidences].first
      expect(evidence[:snippet].length).to eq(20)
      expect(evidence[:raw]).to include(:content_ref)
    end

    it 'maps global filters to search options' do
      expect(smart_rag).to receive(:search).with(
        'filter map query',
        hash_including(
          document_ids: [1, 2],
          tag_ids: [3],
          date_from: '2026-02-01T00:00:00Z',
          date_to: '2026-02-20T00:00:00Z'
        )
      ).and_return({ results: [] })

      smart_rag.retrieve(
        plan: {
          version: '0.1',
          request_id: 'req-filter-map',
          queries: [{ text: 'filter map query', mode: 'hybrid', weight: 1.0 }],
          global_filters: {
            document_ids: [1, 2],
            tag_ids: [3],
            time_range: {
              from: '2026-02-01T00:00:00Z',
              to: '2026-02-20T00:00:00Z'
            }
          }
        }
      )
    end

    it 'maps query modes to underlying search types' do
      expect(smart_rag).to receive(:search)
        .with('exact query', hash_including(search_type: 'fulltext'))
        .and_return({ results: [] })

      expect(smart_rag).to receive(:search)
        .with('semantic query', hash_including(search_type: 'vector'))
        .and_return({ results: [] })

      expect(smart_rag).to receive(:search)
        .with('hybrid query', hash_including(search_type: 'hybrid'))
        .and_return({ results: [] })

      plan = {
        version: '0.1',
        request_id: 'req-002',
        queries: [
          { text: 'exact query', mode: 'exact', weight: 1.0 },
          { text: 'semantic query', mode: 'semantic', weight: 1.0 },
          { text: 'hybrid query', mode: 'hybrid', weight: 1.0 }
        ],
        budget: {
          top_k: 10,
          per_mode_k: { exact: 3, semantic: 3, hybrid: 3 }
        }
      }

      pack = smart_rag.retrieve(plan: plan)
      expect(pack[:evidences]).to eq([])
      expect(pack.dig(:stats, :candidates)).to eq(0)
    end

    it 'applies source_type/source_uri_prefix filters and topic_ids filter' do
      allow(smart_rag).to receive(:search).and_return(
        {
          results: [
            {
              section: { id: 1, document_id: 11, content: 'url doc' },
              metadata: { source_uri: 'https://example.com/a', source_type: 'url' }
            },
            {
              section: { id: 2, document_id: 12, content: 'file doc' },
              metadata: { source_uri: 'file:///tmp/a.md', source_type: 'file' }
            }
          ]
        }
      )
      allow_any_instance_of(SmartRAG::Retrieve).to receive(:section_topic_ids_for) do |_instance, section_id|
        case section_id
        when 1 then [2]
        when 2 then [3]
        else []
        end
      end

      plan = {
        version: '0.1',
        request_id: 'req-003',
        queries: [
          { text: 'filter query', mode: 'hybrid', weight: 1.0 }
        ],
        global_filters: {
          source_type: ['url'],
          source_uri_prefix: ['https://example.com/'],
          topic_ids: [1, 2]
        }
      }

      pack = smart_rag.retrieve(plan: plan)
      ignored = pack.dig(:explain, :ignored_fields) || []
      evidences = pack[:evidences]

      expect(ignored).not_to include('global_filters.topic_ids not supported')
      expect(evidences.length).to eq(1)
      expect(evidences.first[:source_type]).to eq('url')
      expect(pack.dig(:explain, :filters_applied, :source_type)).to eq(['url'])
      expect(pack.dig(:explain, :filters_applied, :topic_ids)).to eq([1, 2])
    end
  end
end
