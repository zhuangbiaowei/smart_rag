#!/usr/bin/env ruby

require './lib/smart_rag'
require 'sequel'
require 'logger'

# Update document languages and rebuild FTS indexes
class LanguageFixer
  def initialize
    @db = Sequel.connect('postgresql://rag_user:rag_pwd@localhost/smart_rag_development')
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
  end

  # Detect language from text
  def detect_language(text)
    return 'en' if text.nil? || text.empty?

    if text =~ /[\u3040-\u309f\u30a0-\u30ff]/
      'ja'
    elsif text =~ /[\uac00-\ud7af]/
      'ko'
    elsif text =~ /[\u4e00-\u9fff]/
      'zh'
    else
      'en'
    end
  end

  # Update document languages
  def update_document_languages
    @logger.info('Updating document languages...')

    docs = @db[:source_documents].all
    updated = 0

    docs.each do |doc|
      # Get content from sections
      sections = @db[:source_sections].where(document_id: doc[:id]).limit(3).all

      next unless sections.any?

      # Detect language from first section content
      content = sections.map { |s| s[:content] }.join("\n")
      detected_lang = detect_language(content)

      next unless detected_lang != doc[:language]

      @db[:source_documents].where(id: doc[:id]).update(language: detected_lang)
      @logger.info("  Updated doc #{doc[:id]} '#{doc[:title]}': #{doc[:language]} -> #{detected_lang}")
      updated += 1
    end

    @logger.info("Updated #{updated} document languages")
  end

  # Rebuild FTS indexes
  def rebuild_fts_indexes
    @logger.info('Rebuilding FTS indexes...')

    # Delete existing FTS records
    deleted = @db[:section_fts].delete
    @logger.info("Deleted #{deleted} old FTS records")

    # Trigger FTS rebuild by updating sections
    sections = @db[:source_sections].all

    sections.each_with_index do |section, index|
      @logger.info("  Processed #{index + 1}/#{sections.length} sections") if (index + 1) % 100 == 0

      # Trigger the update_section_fts function by updating each section
      @db[:source_sections].where(id: section[:id]).update(updated_at: Sequel::CURRENT_TIMESTAMP)
    end

    @logger.info("Rebuilt FTS indexes for #{sections.length} sections")
  end

  # Verify FTS data
  def verify_fts_data
    @logger.info('Verifying FTS data...')

    # Check language distribution
    langs = @db[:section_fts].group_and_count(:language).all
    @logger.info('Language distribution:')
    langs.each { |l| @logger.info("  #{l[:language]}: #{l[:count]}") }

    # Sample FTS records
    samples = @db[:section_fts].join(:source_sections, id: :section_id).select(:section_fts__section_id___section_id,
                                                                               :section_title, :language).limit(5).all
    @logger.info('Sample FTS records:')
    samples.each { |s| @logger.info("  Section #{s[:section_id]}: #{s[:section_title]} (lang: #{s[:language]})") }
  end

  def run
    @logger.info('=' * 60)
    @logger.info('Starting language fix and FTS rebuild')
    @logger.info('=' * 60)

    update_document_languages
    rebuild_fts_indexes
    verify_fts_data

    @logger.info('=' * 60)
    @logger.info('Done!')
    @logger.info('=' * 60)
  end
end

# Run the fixer
if __FILE__ == $0
  fixer = LanguageFixer.new
  fixer.run
end
