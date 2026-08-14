# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'json'
require 'rack/mock'
require 'smart_rag'
require 'smart_rag/http_app'
require 'smart_rag/http_access_policy'
require_relative '../support/database_helpers'

RSpec.describe 'media document principal isolation', type: :integration do
  before(:all) do
    @db = Sequel.connect(DatabaseHelpers.test_db_config)
    Sequel.extension :migration
    Sequel::Migrator.run(@db, File.expand_path('../../db/migrations', __dir__))
    SmartRAG.db = @db
    SmartRAG::Models.db = @db
    SmartRAG::Models::SourceDocument.set_dataset(@db[:source_documents])
    SmartRAG::Models::SourceSection.set_dataset(@db[:source_sections])
  end

  after(:all) { @db&.disconnect }
  around { |example| @db.transaction(rollback: :always) { example.run } }

  let(:rag) do
    SmartRAG::SmartRAG.allocate.tap do |instance|
      instance.instance_variable_set(:@logger, Logger.new(nil))
    end
  end

  it 'isolates document reads, lists, deletion, search, and statistics' do
    alice = @db[:source_documents].insert(title: 'Alice secret', url: 'alice', principal: 'alice')
    bob = @db[:source_documents].insert(title: 'Bob secret', url: 'bob', principal: 'bob')
    alice_section = @db[:source_sections].insert(document_id: alice, content: 'alice roadmap')
    @db[:source_sections].insert(document_id: bob, content: 'bob roadmap')

    expect(rag.get_document(alice, principal: 'alice')[:id]).to eq(alice)
    expect(rag.get_document(bob, principal: 'alice')).to be_nil
    expect(rag.list_documents(principal: 'alice')[:documents].map { |doc| doc[:id] }).to contain_exactly(alice)
    expect(rag.statistics(principal: 'alice')).to include(document_count: 1, section_count: 1)

    allow(rag).to receive(:hybrid_search).and_return(
      results: [{ section: { id: alice_section, document_id: alice, content: 'alice roadmap' } }]
    )
    scoped = rag.search('roadmap', search_type: 'hybrid', principal: 'bob')
    expect(scoped[:results]).to eq([])
    expect(rag).to have_received(:hybrid_search).with(
      'roadmap', hash_including(document_ids: [bob], principal: 'bob')
    )

    expect(rag.remove_document(bob, principal: 'alice')[:success]).to eq(false)
    expect(@db[:source_documents].where(id: bob).count).to eq(1)
  end

  it 'filters retrieval candidates even when a backend ignores document_ids' do
    alice = @db[:source_documents].insert(title: 'Alice', url: 'alice-r', principal: 'alice', metadata: '{}')
    bob = @db[:source_documents].insert(title: 'Bob', url: 'bob-r', principal: 'bob', metadata: '{}')
    alice_section = @db[:source_sections].insert(document_id: alice, content: 'shared term')
    bob_section = @db[:source_sections].insert(document_id: bob, content: 'shared term')
    allow(rag).to receive(:search).and_return(results: [
      { section: { id: alice_section, document_id: alice, content: 'alice' } },
      { section: { id: bob_section, document_id: bob, content: 'bob' } }
    ])

    pack = SmartRAG::Retrieve.new(rag).execute(
      plan: { _principal: 'alice', queries: [{ text: 'shared', mode: 'hybrid' }] }
    )
    expect(pack[:evidences].map { |item| item[:document_id] }).to eq([alice])
    expect(pack.dig(:plan, :global_filters)).not_to have_key(:principal)
  end

  it 'isolates retrieval through real bearer authentication and HTTP dispatch' do
    alice = @db[:source_documents].insert(title: 'Alice', url: 'alice-http', principal: 'alice', metadata: '{}')
    bob = @db[:source_documents].insert(title: 'Bob', url: 'bob-http', principal: 'bob', metadata: '{}')
    alice_section = @db[:source_sections].insert(document_id: alice, content: 'alice confidential roadmap')
    bob_section = @db[:source_sections].insert(document_id: bob, content: 'bob confidential roadmap')
    allow(rag).to receive(:search).and_return(results: [
      { section: { id: alice_section, document_id: alice, content: 'alice confidential roadmap' } },
      { section: { id: bob_section, document_id: bob, content: 'bob confidential roadmap' } }
    ])
    policy = SmartRAG::HttpAccessPolicy.new(
      db: @db, config: { enabled: true, tokens: { alice: 'alice-token', bob: 'bob-token' } }
    )
    app = SmartRAG::HttpApp.new(rag: rag, access_policy: policy)
    request = lambda do |token|
      env = Rack::MockRequest.env_for(
        '/v1/retrieve', method: 'POST',
        input: JSON.generate(plan: { queries: [{ text: 'confidential roadmap', mode: 'hybrid' }] }),
        'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}"
      )
      status, _headers, body = app.call(env)
      [status, JSON.parse(body.join, symbolize_names: true)]
    end

    alice_status, alice_body = request.call('alice-token')
    bob_status, bob_body = request.call('bob-token')
    invalid_status, = request.call('invalid-token')

    expect(alice_status).to eq(200)
    expect(alice_body[:evidences].map { |item| item[:document_id] }).to eq([alice])
    expect(bob_status).to eq(200)
    expect(bob_body[:evidences].map { |item| item[:document_id] }).to eq([bob])
    expect(invalid_status).to eq(401)
  end
end
