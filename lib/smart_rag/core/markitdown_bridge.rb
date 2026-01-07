require 'json'
require 'tempfile'
require 'open3'

module SmartRAG
  module Core
    # Bridge to Python markitdown library
    class MarkitdownBridge
      class ConversionError < StandardError; end
      class UnsupportedFormatError < StandardError; end

      def initialize
        @python_available = check_python_markitdown
      end

      # Convert a file to markdown
      # @param [String] file_path Path to the file to convert
      # @return [String] Converted markdown content
      def convert(file_path)
        raise ConversionError, "Markitdown is not available" unless @python_available
        raise ConversionError, "File not found: #{file_path}" unless File.exist?(file_path)

        result = call_python_convert(file_path)

        if result.nil? || result.empty?
          raise ConversionError, "Conversion returned empty result"
        end

        result
      rescue StandardError => e
        raise ConversionError, "Failed to convert #{file_path}: #{e.message}"
      end

      # Check if markitdown is available
      # @return [Boolean]
      def available?
        @python_available
      end

      private

      def check_python_markitdown
        system("python3 -c \"import markitdown\" 2>/dev/null")
      end

      def call_python_convert(file_path)
        script = <<~PYTHON
          import sys
          import json
          from markitdown import MarkItDown
          from pathlib import Path

          try:
              md = MarkItDown()
              result = md.convert("#{file_path}")
              # Return just the text content
              print(result.text_content)
          except Exception as e:
              print(f"ERROR: {str(e)}", file=sys.stderr)
              sys.exit(1)
        PYTHON

        output, status = Open3.capture2e("python3", "-c", script)

        if status.success?
          output
        else
          raise ConversionError, output
        end
      end
    end
  end
end
