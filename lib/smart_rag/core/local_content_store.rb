# frozen_string_literal: true

require 'digest'
require 'fileutils'

module SmartRAG
  module Core
    class LocalContentStore
      def initialize(root:)
        @root = File.expand_path(root)
        FileUtils.mkdir_p(@root)
      end

      def put(file_path)
        digest = Digest::SHA256.file(file_path).hexdigest
        extension = File.extname(file_path).downcase
        destination = File.join(root, digest[0, 2], digest[2, 2], "#{digest}#{extension}")
        FileUtils.mkdir_p(File.dirname(destination))
        copy_atomically(file_path, destination) unless File.exist?(destination)
        { content_hash: digest, storage_uri: "file://#{destination}", stored_path: destination }
      end

      def delete(storage_uri)
        path = storage_uri.to_s.delete_prefix('file://')
        return false unless path.start_with?("#{root}#{File::SEPARATOR}") && File.file?(path)

        File.delete(path)
        true
      end

      def materialize(storage_uri)
        path = storage_uri.to_s.delete_prefix('file://')
        raise ArgumentError, 'storage URI does not belong to this local store' unless path.start_with?("#{root}#{File::SEPARATOR}")
        raise ArgumentError, 'stored media object is missing' unless File.file?(path)
        [path, false]
      end

      private

      attr_reader :root

      def copy_atomically(source, destination)
        temporary = "#{destination}.#{Process.pid}.tmp"
        FileUtils.cp(source, temporary)
        File.rename(temporary, destination)
      ensure
        File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
      end
    end
  end
end
