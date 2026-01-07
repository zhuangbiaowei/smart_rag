module SmartRAG
  module Errors
    # Base error class for all SmartRAG errors
    class BaseError < StandardError
      attr_reader :context

      def initialize(message, context = {})
        super(message)
        @context = context
      end
    end

    # Document processing errors
    class DocumentProcessingError < BaseError; end
    class DocumentDownloadError < DocumentProcessingError; end
    class DocumentConversionError < DocumentProcessingError; end
    class ChunkingError < DocumentProcessingError; end

    # Search errors (extend existing ones from fulltext_manager.rb)
    class SearchError < BaseError
      def initialize(message, context = {})
        super("Search failed: #{message}", context)
      end
    end

    class VectorSearchError < SearchError; end
    class QueryParseError < SearchError; end
    class LanguageDetectionError < SearchError; end
    class QueryProcessingError < SearchError; end
    class FulltextSearchError < SearchError; end
    class HybridSearchError < SearchError; end

    # Embedding errors
    class EmbeddingError < BaseError; end
    class EmbeddingGenerationError < EmbeddingError; end
    class EmbeddingStorageError < EmbeddingError; end
    class EmbeddingNotFoundError < EmbeddingError; end

    # Tag generation errors
    class TagError < BaseError; end
    class TagGenerationError < TagError; end
    class TagStorageError < TagError; end

    # Database errors
    class DatabaseError < BaseError; end
    class MigrationError < DatabaseError; end
    class ConnectionError < DatabaseError; end

    # Configuration errors
    class ConfigError < BaseError; end
    class InvalidConfigError < ConfigError; end
    class MissingConfigError < ConfigError; end

    # Service errors
    class ServiceError < BaseError
      def initialize(message, context = {})
        super("Service error: #{message}", context)
      end
    end
    class EmbeddingServiceError < ServiceError; end
    class VectorSearchServiceError < ServiceError; end
    class FulltextSearchServiceError < ServiceError; end
    class HybridSearchServiceError < ServiceError; end
    class SummarizationServiceError < ServiceError; end
    class TagServiceError < ServiceError; end
    class QueryProcessingServiceError < ServiceError; end
    class ResponseGenerationError < ServiceError; end

    # LLM integration errors
    class LLMError < BaseError; end
    class LLMConnectionError < LLMError; end
    class LLMRateLimitError < LLMError; end
    class LLMTimeoutError < LLMError; end
    class LLMResponseError < LLMError; end
    class LLMConfigurationError < LLMError; end
    class ExternalServiceUnavailable < LLMError; end
    class ContextTooLarge < LLMError; end

    # Parser errors
    class ParserError < BaseError; end
    class QueryParserError < ParserError; end

    # Validation errors
    class ValidationError < BaseError; end
    class InvalidQueryError < ValidationError; end
    class InvalidParameterError < ValidationError; end
  end
end
