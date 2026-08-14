# frozen_string_literal: true

require_relative 'media_job_queue'

module SmartRAG
  module Core
    class MediaObjectRegistry
      def initialize(db:, content_store:)
        @db = db
        @content_store = content_store
      end

      def attach(document_id, stored, byte_size:)
        return unless stored

        db.transaction(savepoint: true) do
          object_id = register(stored, byte_size: byte_size)
          detach_document(document_id, except_object_id: object_id)
          inserted = db[:media_object_references].insert_conflict.insert(
            media_object_id: object_id, document_id: document_id, created_at: Time.now
          )
          db[:media_objects].where(id: object_id).update(
            reference_count: db[:media_object_references].where(media_object_id: object_id).count,
            updated_at: Time.now
          ) if inserted
        end
      end

      def register(stored, byte_size:)
        db[:media_objects].insert_conflict(target: :content_hash).insert(
          content_hash: stored[:content_hash], storage_uri: stored[:storage_uri], byte_size: byte_size,
          reference_count: 0, created_at: Time.now, updated_at: Time.now
        )
        db[:media_objects].where(content_hash: stored[:content_hash]).for_update.get(:id)
      end

      def detach_document(document_id, except_object_id: nil)
        refs = db[:media_object_references].where(document_id: document_id)
        refs = refs.exclude(media_object_id: except_object_id) if except_object_id
        object_ids = refs.select_map(:media_object_id)
        refs.delete
        object_ids.each { |id| refresh_count(id) }
        object_ids
      end

      def garbage_collect(limit: 100)
        removed = []
        staged_ids = db.table_exists?(:media_jobs) ? db[:media_jobs].exclude(staging_media_object_id: nil).select(:staging_media_object_id) : []
        candidate_ids = db[:media_objects].where(reference_count: 0)
                                  .exclude(id: staged_ids).order(:id)
                                  .limit(limit.to_i.clamp(1, 1000)).select_map(:id)
        candidate_ids.each do |object_id|
          db.transaction do
            object = db[:media_objects].where(id: object_id).for_update.first
            next unless object
            next unless db[:media_object_references].where(media_object_id: object_id).count.zero?

            content_store.delete(object[:storage_uri])
            removed << object_id if db[:media_objects].where(id: object_id).delete == 1
          end
        end
        { removed_count: removed.length, object_ids: removed }
      end

      def object_id_for(content_hash)
        db[:media_objects].where(content_hash: content_hash).get(:id)
      end

      private

      attr_reader :db, :content_store

      def refresh_count(object_id)
        count = db[:media_object_references].where(media_object_id: object_id).count
        db[:media_objects].where(id: object_id).update(reference_count: count, updated_at: Time.now)
      end
    end
  end
end
