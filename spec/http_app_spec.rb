# frozen_string_literal: true

require 'unit_spec_helper'
require 'json'
require 'rack/mock'
require 'tempfile'
require 'smart_rag/http_app'

RSpec.describe SmartRAG::HttpApp do
  let(:rag) { double('rag') }
  let(:app) { described_class.new(rag: rag, extractors: { image_describer: :server_extractor }) }

  def response_for(method, path, **options)
    env = Rack::MockRequest.env_for(path, { method: method }.merge(options))
    status, _headers, body = app.call(env)
    [status, JSON.parse(body.join, symbolize_names: true)]
  end

  it 'imports a URL from JSON and injects server extractors' do
    allow(rag).to receive(:add_image).with(
      'https://example.com/photo.jpg',
      hash_including(title: 'Photo', image_describer: :server_extractor)
    ).and_return(document_id: 1, media_type: 'image', status: 'success')

    status, body = response_for(
      'POST', '/v1/media',
      input: JSON.generate(operation: 'add_image', source: 'https://example.com/photo.jpg',
                           options: { title: 'Photo' }),
      'CONTENT_TYPE' => 'application/json'
    )

    expect(status).to eq(200)
    expect(body).to include(document_id: 1, media_type: 'image')
  end

  it 'imports a multipart file while preserving its extension' do
    file = Tempfile.new(['photo', '.jpg'])
    file.write('image bytes')
    file.close
    upload = Rack::Multipart::UploadedFile.new(file.path, 'image/jpeg', true, filename: 'photo.jpg')
    allow(rag).to receive(:add_media) do |source, options|
      expect(File.extname(source)).to eq('.jpg')
      expect(File.binread(source)).to eq('image bytes')
      expect(options).to include(tags: ['roadmap'], image_describer: :server_extractor)
      { document_id: 2, media_type: 'image', status: 'success' }
    end

    status, body = response_for(
      'POST', '/v1/media',
      params: { operation: 'add_media', options: JSON.generate(tags: ['roadmap']), file: upload }
    )

    expect(status).to eq(200)
    expect(body[:document_id]).to eq(2)
  ensure
    file&.unlink
  end

  it 'executes retrieval plans' do
    allow(rag).to receive(:retrieve).with(plan: hash_including(request_id: 'r1')).and_return(
      version: '0.1', request_id: 'r1', evidences: []
    )
    status, body = response_for(
      'POST', '/v1/retrieve', input: JSON.generate(plan: { request_id: 'r1' }),
      'CONTENT_TYPE' => 'application/json'
    )

    expect(status).to eq(200)
    expect(body[:request_id]).to eq('r1')
  end

  it 'queues multipart uploads in durable temporary storage' do
    file = Tempfile.new(['queued', '.jpg'])
    file.write('queued image')
    file.close
    upload = Rack::Multipart::UploadedFile.new(file.path, 'image/jpeg', true, filename: 'queued.jpg')
    queued_source = nil
    allow(rag).to receive(:enqueue_media) do |source, options|
      queued_source = source
      expect(File.binread(source)).to eq('queued image')
      expect(options).to include(operation: :add_image, delete_source_after: true)
      { job_id: 4, status: 'queued' }
    end

    status, body = response_for(
      'POST', '/v1/media',
      params: { operation: 'add_image', options: JSON.generate(async: true), file: upload }
    )

    expect(status).to eq(202)
    expect(body).to include(job_id: 4, status: 'queued')
    expect(File).to exist(queued_source)
  ensure
    File.delete(queued_source) if queued_source && File.exist?(queued_source)
    file&.unlink
  end

  it 'stages asynchronous uploads in configured shared storage' do
    file = Tempfile.new(['shared', '.jpg'])
    file.write('shared image')
    file.close
    upload = Rack::Multipart::UploadedFile.new(file.path, 'image/jpeg', true, filename: 'shared.jpg')
    allow(rag).to receive(:stage_media_upload) do |source|
      expect(File.binread(source)).to eq('shared image')
      { storage_uri: 's3://media/shared.jpg', content_hash: 'abc' }
    end
    allow(rag).to receive(:enqueue_media).with(
      's3://media/shared.jpg', hash_including(operation: :add_image)
    ).and_return(job_id: 6, status: 'queued')

    status, body = response_for(
      'POST', '/v1/media',
      params: { operation: 'add_image', options: JSON.generate(async: true), file: upload }
    )
    expect(status).to eq(202)
    expect(body[:job_id]).to eq(6)
  ensure
    file&.unlink
  end

  it 'returns media job status' do
    allow(rag).to receive(:media_job).with('12').and_return(id: 12, status: 'completed')
    status, body = response_for('GET', '/v1/media/jobs/12')
    expect(status).to eq(200)
    expect(body).to include(id: 12, status: 'completed')
  end

  it 'returns 404 for an unknown media job' do
    allow(rag).to receive(:media_job).with('99').and_return(nil)
    status, body = response_for('GET', '/v1/media/jobs/99')
    expect(status).to eq(404)
    expect(body[:error]).to eq('media job not found')
  end

  it 'lists, cancels, retries, and reports media jobs' do
    allow(rag).to receive(:media_jobs).with(status: 'failed', limit: '5', offset: '0')
      .and_return(jobs: [{ id: 3, status: 'failed' }], total: 1)
    allow(rag).to receive(:cancel_media_job).with('3').and_return(id: 3, status: 'canceled')
    allow(rag).to receive(:retry_media_job).with('3').and_return(id: 3, status: 'queued')
    allow(rag).to receive(:media_job_statistics).and_return(counts: { queued: 1 }, total: 1)

    status, body = response_for('GET', '/v1/media/jobs?status=failed&limit=5&offset=0')
    expect(status).to eq(200)
    expect(body[:total]).to eq(1)
    expect(response_for('POST', '/v1/media/jobs/3/cancel').last[:status]).to eq('canceled')
    expect(response_for('POST', '/v1/media/jobs/3/retry').last[:status]).to eq('queued')
    expect(response_for('GET', '/v1/media/jobs/stats').last[:total]).to eq(1)
  end

  it 'returns conflict for an invalid job transition' do
    allow(rag).to receive(:cancel_media_job).with('8').and_return(
      id: 8, status: 'processing', transition_error: 'only queued jobs can be canceled'
    )
    status, body = response_for('POST', '/v1/media/jobs/8/cancel')
    expect(status).to eq(409)
    expect(body[:transition_error]).to include('only queued')
  end

  it 'maps idempotency payload conflicts to HTTP 409' do
    allow(rag).to receive(:enqueue_media)
      .and_raise(SmartRAG::Core::MediaJobQueue::IdempotencyConflict, 'different request payload')
    status, body = response_for(
      'POST', '/v1/media',
      input: JSON.generate(operation: 'add_image', source: 'https://example.com/a.jpg',
                           options: { async: true, idempotency_key: 'same-key' }),
      'CONTENT_TYPE' => 'application/json'
    )

    expect(status).to eq(409)
    expect(body).to include(code: 'idempotency_conflict')
  end

  it 'includes queue metrics in health checks when supported' do
    allow(rag).to receive(:media_job_statistics).and_return(counts: { queued: 2 }, total: 2)
    status, body = response_for('GET', '/healthz')
    expect(status).to eq(200)
    expect(body.dig(:media_jobs, :total)).to eq(2)
  end

  it 'reports degraded health when queue diagnostics fail' do
    allow(rag).to receive(:media_job_statistics).and_raise('migration missing')
    status, body = response_for('GET', '/healthz')
    expect(status).to eq(503)
    expect(body).to include(status: 'degraded')
    expect(body[:error]).to include('migration missing')
  end

  it 'requires authentication and scopes jobs to the principal' do
    policy = double('policy')
    allow(policy).to receive(:authorize!).and_return('alice')
    allow(policy).to receive(:consume!)
    secured = described_class.new(rag: rag, access_policy: policy)
    allow(rag).to receive(:media_job).with('12', principal: 'alice').and_return(id: 12, status: 'queued')
    env = Rack::MockRequest.env_for('/v1/media/jobs/12', method: 'GET')
    status, _headers, body = secured.call(env)
    expect(status).to eq(200)
    expect(JSON.parse(body.join)['id']).to eq(12)
  end

  it 'injects the authenticated principal into retrieval and synchronous ingestion' do
    policy = double('policy')
    allow(policy).to receive(:authorize!).and_return('alice')
    allow(policy).to receive(:consume!)
    secured = described_class.new(rag: rag, access_policy: policy)
    allow(rag).to receive(:retrieve).with(plan: hash_including(_principal: 'alice'))
      .and_return(evidences: [])
    allow(rag).to receive(:add_image).with(
      'https://example.com/a.jpg', hash_including(principal: 'alice')
    ).and_return(status: 'success')

    env = Rack::MockRequest.env_for('/v1/retrieve', method: 'POST',
                                    input: JSON.generate(plan: { queries: [{ text: 'x' }] }),
                                    'CONTENT_TYPE' => 'application/json')
    expect(secured.call(env).first).to eq(200)
    env = Rack::MockRequest.env_for('/v1/media', method: 'POST',
                                    input: JSON.generate(operation: 'add_image', source: 'https://example.com/a.jpg'),
                                    'CONTENT_TYPE' => 'application/json')
    expect(secured.call(env).first).to eq(200)
  end

  it 'maps authentication and quota failures to HTTP status codes' do
    policy = double('policy')
    secured = described_class.new(rag: rag, access_policy: policy)
    allow(policy).to receive(:authorize!).and_raise(SmartRAG::HttpAccessPolicy::Unauthorized, 'bad token')
    status, = secured.call(Rack::MockRequest.env_for('/v1/media/jobs', method: 'GET'))
    expect(status).to eq(401)

    allow(policy).to receive(:authorize!).and_return('alice')
    allow(policy).to receive(:consume!).and_raise(SmartRAG::HttpAccessPolicy::QuotaExceeded, 'quota')
    status, = secured.call(Rack::MockRequest.env_for('/v1/media/jobs', method: 'GET'))
    expect(status).to eq(429)
  end

  it 'rejects unknown write operations' do
    status, body = response_for(
      'POST', '/v1/media', input: JSON.generate(operation: 'remove_document', source: 'x'),
      'CONTENT_TYPE' => 'application/json'
    )

    expect(status).to eq(400)
    expect(body[:error]).to include('unsupported operation')
  end
end
