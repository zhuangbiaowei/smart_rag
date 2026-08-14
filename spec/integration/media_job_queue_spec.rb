# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'smart_rag/core/media_job_queue'
require_relative '../support/database_helpers'

RSpec.describe SmartRAG::Core::MediaJobQueue, type: :integration do
  before(:all) do
    @db = Sequel.connect(DatabaseHelpers.test_db_config)
    Sequel.extension :migration
    Sequel::Migrator.run(@db, File.expand_path('../../db/migrations', __dir__))
  end

  after(:all) { @db&.disconnect }

  around do |example|
    @db.transaction(rollback: :always) { example.run }
  end

  it 'claims and completes a queued job using PostgreSQL locking' do
    queue = described_class.new(db: @db, handler: ->(operation, source, options) {
      expect([operation, source, options.dig(:metadata, :kind)]).to eq([:add_media, '/tmp/a.mp3', 'meeting'])
      { status: 'success', document_id: 22 }
    })
    job = queue.enqueue(operation: :add_media, source: '/tmp/a.mp3',
                        options: { metadata: { kind: 'meeting' } })

    result = queue.run_one
    expect(result).to include(id: job[:id], status: 'completed', attempts: 1)
    expect(result.dig(:result, 'document_id')).to eq(22)
  end

  it 'retries and ultimately fails a broken job' do
    queue = described_class.new(db: @db, handler: ->(*) { raise 'broken extractor' })
    job = queue.enqueue(operation: :add_image, source: '/tmp/a.jpg', max_attempts: 2)

    retrying = queue.run_one
    expect(retrying).to include(id: job[:id], status: 'queued', attempts: 1)
    expect(retrying[:available_at]).to be > retrying[:updated_at]

    @db[:media_jobs].where(id: job[:id]).update(available_at: Sequel.function(:clock_timestamp))
    result = queue.run_one
    expect(result).to include(id: job[:id], status: 'failed', attempts: 2)
    expect(result[:error]).to include('broken extractor')
  end

  it 'lists, cancels, and manually retries jobs with guarded transitions' do
    queue = described_class.new(db: @db, handler: ->(*) { raise 'broken' })
    queued = queue.enqueue(operation: :add_image, source: '/tmp/list.jpg')
    listing = queue.list(status: 'queued', limit: 10)
    expect(listing[:jobs].map { |item| item[:id] }).to include(queued[:id])

    canceled = queue.cancel(queued[:id])
    expect(canceled[:status]).to eq('canceled')
    expect(queue.retry_job(queued[:id])[:transition_error]).to include('only failed')

    failed = queue.enqueue(operation: :add_image, source: '/tmp/retry.jpg', max_attempts: 1)
    queue.run_one
    expect(queue.retry_job(failed[:id])).to include(status: 'queued', attempts: 0, error: nil)
  end

  it 'recovers stale processing jobs, reports statistics, and prunes terminal jobs' do
    now = Time.now
    queue = described_class.new(db: @db, handler: ->(*) {}, clock: -> { now })
    stale = queue.enqueue(operation: :add_video, source: '/tmp/stale.mp4')
    @db[:media_jobs].where(id: stale[:id]).update(
      status: 'processing', started_at: now - 1000, updated_at: now - 1000
    )
    old = queue.enqueue(operation: :add_audio, source: '/tmp/old.mp3')
    @db[:media_jobs].where(id: old[:id]).update(
      status: 'completed', finished_at: now - 1000, updated_at: now - 1000
    )

    expect(queue.statistics(stale_after_seconds: 900)).to include(stale_processing: 1)
    expect(queue.recover_stale(timeout_seconds: 900)).to eq(1)
    expect(queue.job(stale[:id])).to include(status: 'queued', error: 'worker lease expired; job requeued')
    expect(queue.prune(retention_seconds: 900)).to eq(1)
    expect(queue.job(old[:id])).to be_nil
  end
end
