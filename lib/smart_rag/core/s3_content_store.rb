# frozen_string_literal: true

require 'digest'
require 'tempfile'

module SmartRAG
  module Core
    class S3ContentStore
      def initialize(bucket:, region: nil, prefix: 'smart-rag/media', endpoint: nil,
                     force_path_style: false, access_key_id: nil, secret_access_key: nil, client: nil)
        @bucket = bucket.to_s
        raise ArgumentError, 'media.content_store.bucket is required' if @bucket.empty?
        @prefix = prefix.to_s.sub(%r{\A/+|/+$}, '')
        @client = client || build_client(region:, endpoint:, force_path_style:, access_key_id:, secret_access_key:)
      end

      def put(file_path)
        digest = Digest::SHA256.file(file_path).hexdigest
        key = object_key(digest, File.extname(file_path).downcase)
        client.put_object(bucket: bucket, key: key, body: File.open(file_path, 'rb')) unless exists?(key)
        { content_hash: digest, storage_uri: "s3://#{bucket}/#{key}", stored_path: nil }
      end

      def delete(storage_uri)
        key = key_from_uri(storage_uri)
        client.delete_object(bucket: bucket, key: key)
        true
      end

      def materialize(storage_uri)
        key = key_from_uri(storage_uri)
        extension = File.extname(key)
        file = Tempfile.new(['smart-rag-object', extension])
        file.close
        client.get_object(bucket: bucket, key: key, response_target: file.path)
        [file.path, true]
      rescue StandardError
        file&.unlink
        raise
      end

      private

      attr_reader :bucket, :prefix, :client

      def build_client(region:, endpoint:, force_path_style:, access_key_id:, secret_access_key:)
        require 'aws-sdk-s3'
        options = { region: region || 'us-east-1', force_path_style: force_path_style }
        options[:endpoint] = endpoint unless endpoint.to_s.empty?
        unless access_key_id.to_s.empty?
          options[:access_key_id] = access_key_id
          options[:secret_access_key] = secret_access_key
        end
        Aws::S3::Client.new(**options)
      rescue LoadError
        raise LoadError, 'S3 content storage requires the aws-sdk-s3 gem'
      end

      def exists?(key)
        client.head_object(bucket: bucket, key: key)
        true
      rescue StandardError => e
        return false if e.class.name.end_with?('NotFound', 'NoSuchKey')
        raise
      end

      def object_key(digest, extension)
        [prefix, digest[0, 2], digest[2, 2], "#{digest}#{extension}"].reject(&:empty?).join('/')
      end

      def key_from_uri(uri)
        prefix_value = "s3://#{bucket}/"
        raise ArgumentError, 'storage URI does not belong to this S3 store' unless uri.to_s.start_with?(prefix_value)
        uri.to_s.delete_prefix(prefix_value)
      end
    end
  end
end
