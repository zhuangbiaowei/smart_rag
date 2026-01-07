require 'faker'

FactoryBot.define do
  # SourceDocument factory
  factory :source_document, class: 'SmartRAG::Models::SourceDocument' do
    title { Faker::Book.title }
    url { Faker::Internet.url }
    author { Faker::Name.name }
    description { Faker::Lorem.paragraph }
    download_state { 1 } # completed
    language { 'en' }
    publication_date { Date.today - rand(365) }
    created_at { Time.now }
    updated_at { Time.now }
  end

  # SourceSection factory
  factory :source_section, class: 'SmartRAG::Models::SourceSection' do
    section_title { Faker::Lorem.sentence(word_count: 3) }
    section_number { rand(1..10) }
    content { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    created_at { Time.now }
    updated_at { Time.now }

    # Custom initialization to handle document association
    initialize_with do
      doc = FactoryBot.create(:source_document)
      attributes[:document_id] = doc.id
      SmartRAG::Models::SourceSection.new(attributes)
    end
  end

  # Tag factory
  factory :tag, class: 'SmartRAG::Models::Tag' do
    sequence(:name) { |n| "tag_#{n}_#{Faker::Lorem.word}" }
    parent_id { nil }
    created_at { Time.now }
  end

  # ResearchTopic factory
  factory :research_topic, class: 'SmartRAG::Models::ResearchTopic' do
    sequence(:name) { |n| "Topic #{n}: #{Faker::Lorem.sentence(word_count: 3)}" }
    description { Faker::Lorem.paragraph }
  end

  # TextSearchConfig factory
  factory :text_search_config, class: 'SmartRAG::Models::TextSearchConfig' do
    sequence(:language_code) { |n| "lang_#{n}" }
    config_name { 'pg_catalog.simple' }
    is_installed { true }
  end
end
