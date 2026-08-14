# frozen_string_literal: true

require 'digest'
require 'json'

Sequel.migration do
  up do
    alter_table :media_jobs do
      add_column :request_fingerprint, String, size: 64
    end

    self[:media_jobs].select(:id, :operation, :source, :options).each do |job|
      options = begin
        JSON.parse(job[:options].to_s)
      rescue JSON::ParserError
        job[:options].to_s
      end
      canonicalize = lambda do |value|
        case value
        when Hash
          value.keys.map(&:to_s).sort.to_h do |key|
            original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
            [key, canonicalize.call(value[original_key])]
          end
        when Array
          value.map { |item| canonicalize.call(item) }
        else
          value
        end
      end
      payload = { 'operation' => job[:operation].to_s, 'source' => job[:source].to_s,
                  'options' => canonicalize.call(options) }
      self[:media_jobs].where(id: job[:id]).update(
        request_fingerprint: Digest::SHA256.hexdigest(JSON.generate(payload))
      )
    end

    alter_table :media_jobs do
      set_column_not_null :request_fingerprint
    end
  end

  down do
    alter_table :media_jobs do
      drop_column :request_fingerprint
    end
  end
end
