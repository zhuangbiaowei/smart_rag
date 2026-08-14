# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'rack/mock'
require 'sequel'
require 'smart_rag'
require 'smart_rag/core/media_job_queue'
require 'smart_rag/core/media_object_registry'
require 'smart_rag/http_access_policy'
require 'smart_rag/http_app'
require_relative '../support/database_helpers'

RSpec.describe 'media P3 production controls', type: :integration do
  before(:all) do
    @db = Sequel.connect(DatabaseHelpers.test_db_config)
    Sequel.extension :migration
    Sequel::Migrator.run(@db, File.expand_path('../../db/migrations', __dir__))
  end

  after(:all) { @db&.disconnect }
  around { |example| @db.transaction(rollback: :always) { example.run } }

  it 'deduplicates jobs per principal while isolating different principals' do
    queue = SmartRAG::Core::MediaJobQueue.new(db: @db, handler: ->(*) {})
    first = queue.enqueue(operation: :add_image, source: '/tmp/a.jpg',
                          idempotency_key: 'request-1', principal: 'alice')
    duplicate = queue.enqueue(operation: :add_image, source: '/tmp/a.jpg',
                              idempotency_key: 'request-1', principal: 'alice')
    other = queue.enqueue(operation: :add_image, source: '/tmp/a.jpg',
                          idempotency_key: 'request-1', principal: 'bob')

    expect(duplicate).to include(id: first[:id], deduplicated: true)
    expect(other[:id]).not_to eq(first[:id])
    expect(queue.list(principal: 'alice')[:jobs].map { |job| job[:id] }).to contain_exactly(first[:id])
    expect(queue.job(other[:id], principal: 'alice')).to be_nil
  end

  it 'rejects reuse of an idempotency key with a different request payload' do
    queue = SmartRAG::Core::MediaJobQueue.new(db: @db, handler: ->(*) {})
    first = queue.enqueue(operation: :add_image, source: '/tmp/a.jpg',
                          options: { metadata: { title: 'A', labels: %w[x y] } },
                          idempotency_key: 'conflict-1', principal: 'alice')
    duplicate = queue.enqueue(operation: 'add_image', source: '/tmp/a.jpg',
                              options: { 'metadata' => { 'labels' => %w[x y], 'title' => 'A' } },
                              idempotency_key: 'conflict-1', principal: 'alice')

    expect(duplicate).to include(id: first[:id], deduplicated: true)
    expect do
      queue.enqueue(operation: :add_image, source: '/tmp/b.jpg',
                    options: { metadata: { title: 'A', labels: %w[x y] } },
                    idempotency_key: 'conflict-1', principal: 'alice')
    end.to raise_error(SmartRAG::Core::MediaJobQueue::IdempotencyConflict, /different request payload/)
    expect do
      queue.enqueue(operation: :add_image, source: '/tmp/a.jpg',
                    options: { metadata: { title: 'B', labels: %w[x y] } },
                    idempotency_key: 'conflict-1', principal: 'alice')
    end.to raise_error(SmartRAG::Core::MediaJobQueue::IdempotencyConflict)
  end

  it 'preserves idempotency semantics when concurrent inserts race' do
    queues = 2.times.map do
      connection = Sequel.connect(DatabaseHelpers.test_db_config)
      SmartRAG::Core::MediaJobQueue.new(db: connection, handler: ->(*) {})
    end
    gate = Queue.new
    threads = queues.each_with_index.map do |queue, index|
      Thread.new do
        gate.pop
        queue.enqueue(operation: :add_image, source: "/tmp/race-#{index}.jpg",
                      idempotency_key: 'concurrent-conflict', principal: 'race-principal')
      rescue StandardError => e
        e
      end
    end
    2.times { gate << true }
    results = threads.map(&:value)

    expect(results.count { |result| result.is_a?(Hash) }).to eq(1)
    expect(results.count { |result| result.is_a?(SmartRAG::Core::MediaJobQueue::IdempotencyConflict) }).to eq(1)
  ensure
    queues&.each { |queue| queue.send(:db).disconnect }
    cleanup_db = Sequel.connect(DatabaseHelpers.test_db_config)
    cleanup_db[:media_jobs].where(principal: 'race-principal', idempotency_key: 'concurrent-conflict').delete
    cleanup_db.disconnect
  end

  it 'returns HTTP 409 for a real queued request with the same key and different payload' do
    rag = SmartRAG::SmartRAG.allocate
    rag.instance_variable_set(:@config, { media: { async: {} } })
    rag.instance_variable_set(:@logger, Logger.new(nil))
    SmartRAG.db = @db
    policy = SmartRAG::HttpAccessPolicy.new(
      db: @db, config: { enabled: true, tokens: { alice: 'alice-token' } }
    )
    app = SmartRAG::HttpApp.new(rag: rag, access_policy: policy)
    request = lambda do |source|
      env = Rack::MockRequest.env_for(
        '/v1/media', method: 'POST',
        input: JSON.generate(operation: 'add_image', source: source, options: { async: true }),
        'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer alice-token',
        'HTTP_IDEMPOTENCY_KEY' => 'http-conflict'
      )
      status, _headers, body = app.call(env)
      [status, JSON.parse(body.join, symbolize_names: true)]
    end

    first_status, = request.call('https://example.com/a.jpg')
    conflict_status, conflict_body = request.call('https://example.com/b.jpg')

    expect(first_status).to eq(202)
    expect(conflict_status).to eq(409)
    expect(conflict_body).to include(code: 'idempotency_conflict')
    expect(@db[:media_jobs].where(principal: 'alice', idempotency_key: 'http-conflict').count).to eq(1)
  end

  it 'uses heartbeat time for stale lease recovery' do
    now = Time.now
    queue = SmartRAG::Core::MediaJobQueue.new(db: @db, handler: ->(*) {}, clock: -> { now })
    job = queue.enqueue(operation: :add_video, source: '/tmp/a.mp4')
    @db[:media_jobs].where(id: job[:id]).update(
      status: 'processing', started_at: now - 1000, heartbeat_at: now - 10,
      lease_token: 'active', updated_at: now - 10
    )
    expect(queue.recover_stale(timeout_seconds: 60)).to eq(0)
    @db[:media_jobs].where(id: job[:id]).update(heartbeat_at: now - 1000)
    expect(queue.recover_stale(timeout_seconds: 60)).to eq(1)
  end

  it 'tracks object references and removes unreferenced stored objects' do
    deleted = []
    store = double('store')
    allow(store).to receive(:delete) { |uri| deleted << uri; true }
    registry = SmartRAG::Core::MediaObjectRegistry.new(db: @db, content_store: store)
    doc = @db[:source_documents].insert(title: 'media', url: "p3-#{rand(100_000)}")
    stored = { content_hash: 'a' * 64, storage_uri: 's3://media/object' }

    registry.attach(doc, stored, byte_size: 12)
    expect(@db[:media_objects].where(content_hash: 'a' * 64).get(:reference_count)).to eq(1)
    registry.detach_document(doc)
    expect(registry.garbage_collect).to include(removed_count: 1)
    expect(deleted).to eq(['s3://media/object'])
  end

  it 'does not garbage collect a staged object used by a nonterminal job' do
    store = double('store')
    allow(store).to receive(:delete)
    registry = SmartRAG::Core::MediaObjectRegistry.new(db: @db, content_store: store)
    stored = { content_hash: 'b' * 64, storage_uri: 's3://media/staged' }
    object_id = registry.register(stored, byte_size: 8)
    @db[:media_jobs].insert(
      operation: 'add_image', source: stored[:storage_uri], options: '{}', status: 'queued',
      attempts: 0, max_attempts: 3, principal: 'alice', staging_media_object_id: object_id,
      request_fingerprint: '1' * 64,
      available_at: Time.now,
      created_at: Time.now, updated_at: Time.now
    )

    expect(registry.garbage_collect).to include(removed_count: 0)
    expect(store).not_to have_received(:delete)
  end

  it 'protects failed staging objects until the retained job is pruned' do
    store = double('store')
    allow(store).to receive(:delete).and_return(true)
    registry = SmartRAG::Core::MediaObjectRegistry.new(db: @db, content_store: store)
    stored = { content_hash: 'c' * 64, storage_uri: 's3://media/failed-staged' }
    object_id = registry.register(stored, byte_size: 8)
    job_id = @db[:media_jobs].insert(
      operation: 'add_image', source: stored[:storage_uri], options: '{}', status: 'failed',
      attempts: 1, max_attempts: 1, principal: 'alice', staging_media_object_id: object_id,
      request_fingerprint: '2' * 64,
      available_at: Time.now, finished_at: Time.now - 1000, created_at: Time.now - 1000,
      updated_at: Time.now - 1000
    )

    expect(registry.garbage_collect).to include(removed_count: 0)
    @db[:media_jobs].where(id: job_id).delete
    expect(registry.garbage_collect).to include(removed_count: 1)
  end

  it 'enforces shared request quotas per authenticated principal' do
    policy = SmartRAG::HttpAccessPolicy.new(
      db: @db,
      config: { enabled: true, token: 'secret', principal: 'alice',
                quota: { requests_per_minute: 1, upload_bytes_per_day: 5 } }
    )
    request = double('request', get_header: 'Bearer secret')
    expect(policy.authorize!(request)).to eq('alice')
    policy.consume!('alice', request_bytes: 5)
    expect { policy.consume!('alice') }.to raise_error(SmartRAG::HttpAccessPolicy::QuotaExceeded, /request/)
  end
end
