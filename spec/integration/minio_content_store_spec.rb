# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'sequel'
require 'tempfile'
require 'smart_rag/core/s3_content_store'
require 'smart_rag/core/media_object_registry'
require 'smart_rag/core/media_job_queue'
require_relative '../support/database_helpers'

RSpec.describe 'real MinIO content storage', type: :integration do
  before(:all) do
    skip 'set SMARTRAG_MINIO_E2E=1 to run real MinIO integration' unless ENV['SMARTRAG_MINIO_E2E'] == '1'

    require 'aws-sdk-s3'
    @bucket = ENV.fetch('SMARTRAG_MINIO_BUCKET', 'smart-rag-e2e')
    @store_options = {
      bucket: @bucket,
      region: ENV.fetch('SMARTRAG_MINIO_REGION', 'us-east-1'),
      endpoint: ENV.fetch('SMARTRAG_MINIO_ENDPOINT', 'http://127.0.0.1:19000'),
      force_path_style: true,
      access_key_id: ENV.fetch('SMARTRAG_MINIO_ACCESS_KEY', 'smart-rag-e2e'),
      secret_access_key: ENV.fetch('SMARTRAG_MINIO_SECRET_KEY', 'smart-rag-e2e-secret'),
      prefix: "spec/#{Process.pid}"
    }
    client = Aws::S3::Client.new(**@store_options.reject { |key, _| %i[bucket prefix].include?(key) })
    client.create_bucket(bucket: @bucket) unless client.list_buckets.buckets.any? { |item| item.name == @bucket }

    @db = Sequel.connect(DatabaseHelpers.test_db_config)
    Sequel.extension :migration
    Sequel::Migrator.run(@db, File.expand_path('../../db/migrations', __dir__))
  end

  after(:all) { @db&.disconnect }
  around { |example| @db ? @db.transaction(rollback: :always) { example.run } : example.run }

  it 'round-trips bytes across store instances and deletes an unreferenced object from MinIO' do
    source = Tempfile.new(['minio-e2e', '.bin'])
    source.binmode
    source.write("real-minio-content\x00#{SecureRandom.hex(8)}")
    source.close
    writer = SmartRAG::Core::S3ContentStore.new(**@store_options)
    reader = SmartRAG::Core::S3ContentStore.new(**@store_options)

    stored = writer.put(source.path)
    materialized, temporary = reader.materialize(stored[:storage_uri])
    expect(File.binread(materialized)).to eq(File.binread(source.path))
    expect(stored[:content_hash]).to eq(Digest::SHA256.file(source.path).hexdigest)

    registry = SmartRAG::Core::MediaObjectRegistry.new(db: @db, content_store: reader)
    document_id = @db[:source_documents].insert(title: 'MinIO E2E', url: "minio-e2e-#{SecureRandom.uuid}")
    registry.attach(document_id, stored, byte_size: File.size(source.path))
    object_id = registry.object_id_for(stored[:content_hash])
    expect(@db[:media_objects].where(id: object_id).get(:reference_count)).to eq(1)

    registry.detach_document(document_id)
    expect(registry.garbage_collect).to include(removed_count: 1, object_ids: [object_id])
    expect { writer.materialize(stored[:storage_uri]) }.to raise_error(Aws::S3::Errors::NoSuchKey)
  ensure
    File.delete(materialized) if temporary && materialized && File.file?(materialized)
    source&.unlink
  end

  it 'keeps a real MinIO object while a failed staging job is retained' do
    source = Tempfile.new(['minio-failed', '.bin'])
    source.write("failed-job-object-#{SecureRandom.hex(8)}")
    source.close
    writer = SmartRAG::Core::S3ContentStore.new(**@store_options)
    verifier = SmartRAG::Core::S3ContentStore.new(**@store_options)
    stored = writer.put(source.path)
    registry = SmartRAG::Core::MediaObjectRegistry.new(db: @db, content_store: writer)
    object_id = registry.register(stored, byte_size: File.size(source.path))
    job_id = @db[:media_jobs].insert(
      operation: 'add_image', source: stored[:storage_uri], options: '{}', status: 'failed',
      attempts: 1, max_attempts: 1, principal: 'alice', staging_media_object_id: object_id,
      request_fingerprint: Digest::SHA256.hexdigest('failed-job'), available_at: Time.now,
      finished_at: Time.now, created_at: Time.now, updated_at: Time.now
    )

    expect(registry.garbage_collect).to include(removed_count: 0)
    materialized, temporary = verifier.materialize(stored[:storage_uri])
    expect(File.binread(materialized)).to eq(File.binread(source.path))

    @db[:media_jobs].where(id: job_id).delete
    expect(registry.garbage_collect).to include(removed_count: 1, object_ids: [object_id])
    expect { verifier.materialize(stored[:storage_uri]) }.to raise_error(Aws::S3::Errors::NoSuchKey)
  ensure
    File.delete(materialized) if temporary && materialized && File.file?(materialized)
    source&.unlink
  end

  it 'processes an asynchronously staged URI through a separate worker store instance' do
    @db[:media_jobs].where(status: 'queued').update(available_at: Time.now + 3600)
    source = Tempfile.new(['minio-worker', '.bin'])
    source.write("worker-content-#{SecureRandom.hex(8)}")
    source.close
    uploader = SmartRAG::Core::S3ContentStore.new(**@store_options)
    worker_store = SmartRAG::Core::S3ContentStore.new(**@store_options)
    stored = uploader.put(source.path)
    observed = nil
    queue = SmartRAG::Core::MediaJobQueue.new(
      db: @db,
      handler: lambda do |operation, uri, options|
        path, temporary = worker_store.materialize(uri)
        observed = [operation, File.binread(path), options]
        File.delete(path) if temporary && File.file?(path)
        { status: 'success', storage_uri: uri }
      end
    )
    queued = queue.enqueue(operation: :add_audio, source: stored[:storage_uri],
                           options: { media_type: 'audio' }, principal: 'alice')

    completed = queue.run_one
    expect(completed).to include(id: queued[:id], status: 'completed')
    expect(observed).to eq([:add_audio, File.binread(source.path), { media_type: 'audio' }])
  ensure
    uploader&.delete(stored[:storage_uri]) if stored
    source&.unlink
  end
end
