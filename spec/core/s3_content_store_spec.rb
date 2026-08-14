# frozen_string_literal: true

require 'unit_spec_helper'
require 'tempfile'
require 'smart_rag/core/s3_content_store'

RSpec.describe SmartRAG::Core::S3ContentStore do
  let(:client) do
    Class.new do
      class NotFound < StandardError; end
      attr_reader :objects
      def initialize = @objects = {}
      def head_object(bucket:, key:)
        raise NotFound unless objects.key?([bucket, key])
        objects.fetch([bucket, key])
      end
      def put_object(bucket:, key:, body:) = objects[[bucket, key]] = body.read
      def delete_object(bucket:, key:) = objects.delete([bucket, key])
      def get_object(bucket:, key:, response_target:)
        File.binwrite(response_target, objects.fetch([bucket, key]))
      end
    end.new
  end

  it 'stores by content hash, deduplicates, and deletes through the client' do
    file = Tempfile.new(['photo', '.jpg']).tap { |item| item.write('image'); item.close }
    store = described_class.new(bucket: 'media', prefix: 'assets', client: client)

    first = store.put(file.path)
    second = store.put(file.path)
    expect(second).to eq(first)
    expect(client.objects.length).to eq(1)
    expect(first[:storage_uri]).to match(%r{\As3://media/assets/[0-9a-f]{2}/[0-9a-f]{2}/})
    path, temporary = store.materialize(first[:storage_uri])
    expect(temporary).to eq(true)
    expect(File.binread(path)).to eq('image')
    expect(store.delete(first[:storage_uri])).to eq(true)
    expect(client.objects).to be_empty
  ensure
    File.delete(path) if defined?(path) && path && File.exist?(path)
    file&.unlink
  end
end
