# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'timeout'
require 'uri'

module SmartRAG
  module Core
    class MediaSafetyPolicy
      DEFAULT_MAX_BYTES = 50 * 1024 * 1024
      DEFAULT_MAX_DURATION_MS = 2 * 60 * 60 * 1000

      def initialize(config = {})
        @max_bytes = config.fetch(:max_bytes, config.fetch(:max_file_size_mb, 50).to_i * 1024 * 1024)
        @max_duration_ms = config.fetch(:max_duration_ms, DEFAULT_MAX_DURATION_MS).to_i
        @allow_private_urls = config.fetch(:allow_private_urls, false)
        @allowed_hosts = Array(config[:allowed_hosts]).map(&:downcase)
        @command_timeout = config.fetch(:command_timeout_seconds, 120).to_i
      end

      attr_reader :max_bytes, :max_duration_ms, :command_timeout

      def validate_file!(file_path, duration_ms: nil)
        raise ArgumentError, "media file exceeds #{max_bytes} bytes" if File.size(file_path) > max_bytes
        if duration_ms && duration_ms.to_i > max_duration_ms
          raise ArgumentError, "media duration exceeds #{max_duration_ms}ms"
        end
        true
      end

      def validate_url!(source)
        uri = URI.parse(source)
        raise ArgumentError, 'media URL must use http or https' unless %w[http https].include?(uri.scheme)
        raise ArgumentError, 'media URL must not contain credentials' if uri.userinfo
        return true if @allowed_hosts.include?(uri.host.to_s.downcase)
        return true if @allow_private_urls

        addresses = Resolv.getaddresses(uri.host.to_s)
        raise ArgumentError, 'media URL host could not be resolved' if addresses.empty?
        raise ArgumentError, 'media URL resolves to a private or local address' if addresses.any? { |value| private_ip?(value) }
        true
      rescue URI::InvalidURIError => e
        raise ArgumentError, "invalid media URL: #{e.message}"
      end

      def with_timeout(&block)
        Timeout.timeout(command_timeout, &block)
      end

      private

      def private_ip?(value)
        ip = IPAddr.new(value)
        ip.loopback? || ip.private? || ip.link_local? || ip.to_s == '0.0.0.0' || ip.to_s == '::'
      rescue IPAddr::InvalidAddressError
        true
      end
    end
  end
end
