require_relative 'model_base'
require 'sequel/plugins/validation_helpers'

module SmartRAG
  module Models
    # Embedding model for storing vector embeddings of document sections
    class Embedding < Sequel::Model
      include FactoryBotHelpers
      plugin :validation_helpers
      plugin :timestamps

      # Set dataset after database is connected
      def self.set_dataset_from_db
        set_dataset(:embeddings)
      end

      # Add bang methods for FactoryBot compatibility
      def self.create!(attributes = {})
        instance = new(attributes)
        instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(', '))
        instance
      end

      # Relationships
      many_to_one :section, class: '::SmartRAG::Models::SourceSection', key: :source_id

      # Validation
      def validate
        super
        validates_presence %i[source_id vector]
      end

      # Class methods
      class << self
        # Find embeddings by source section
        def by_section(section_id)
          where(source_id: section_id).all
        end

        # Find embeddings by multiple sections
        def by_sections(section_ids)
          where(source_id: section_ids).all
        end

        # Find similar embeddings using cosine distance (pgvector)
        def similar_to(query_vector, limit: 10, threshold: 0.3)
          server_version = db.server_version

          # Format vector for pgvector
          formatted_vector = if query_vector.is_a?(Array)
                               "[#{query_vector.join(',')}]"
                             else
                               query_vector.to_s
                             end

          distance_threshold = 1 - threshold

          dataset = if server_version >= 120_000 # PostgreSQL 12+
                      where(Sequel.lit('(vector <=> ?) < ?', formatted_vector, distance_threshold))
                        .order(Sequel.lit('vector <=> ?', formatted_vector))
                        .limit(limit)
                    else
                      where(Sequel.lit('cosine_distance(vector, ?) < ?', formatted_vector, distance_threshold))
                        .order(Sequel.lit('cosine_distance(vector, ?)', formatted_vector))
                        .limit(limit)
                    end

          dataset.all
        end

        # Batch insert embeddings
        def batch_insert(embedding_data)
          db.transaction do
            dataset.multi_insert(embedding_data)
          end
        end

        # Delete embeddings by section
        def delete_by_section(section_id)
          where(source_id: section_id).delete
        end

        # Delete old embeddings (cleanup)
        def delete_old_embeddings(days: 30)
          where(Sequel.lit('created_at < ?', Time.now - (days * 24 * 60 * 60))).delete
        end
      end

      # Instance methods

      # Return vector as array of floats
      def vector_array
        return nil unless vector

        # Convert pgvector to array
        vector.to_s.gsub(/[<>]/, '').split(',').map(&:to_f)
      end

      # Calculate similarity to another vector
      def similarity_to(other_vector)
        vector_array = self.vector_array
        vector_array_cosine_similarity(vector_array, other_vector)
      end

      private

      def vector_array_cosine_similarity(v1, v2)
        return 0.0 if v1.nil? || v2.nil? || v1.empty? || v2.empty?

        dot_product = v1.zip(v2).map { |a, b| a * b }.sum
        magnitude1 = Math.sqrt(v1.map { |x| x * x }.sum)
        magnitude2 = Math.sqrt(v2.map { |x| x * x }.sum)
        return 0.0 if magnitude1 == 0 || magnitude2 == 0

        dot_product / (magnitude1 * magnitude2)
      end
    end
  end
end
