require "spec_helper"
require "smart_rag/services/tag_service"
require "smart_rag/models/tag"
require "smart_rag/models/source_section"

RSpec.describe SmartRAG::Services::TagService do
  let(:config) { { config_path: "config/llm_config.yml", max_text_length: 200 } }
  let(:service) { described_class.new(config) }

  let(:sample_text) do
    <<-TEXT
Machine learning algorithms enable computers to learn from data and make predictions.
Deep learning, a subset of machine learning, uses neural networks with multiple layers.
These techniques are applied in various domains including computer vision and natural language processing.
    TEXT
  end

  let(:section) do
    instance_double(
      "SmartRAG::Models::SourceSection",
      id: 1,
      section_title: "Machine Learning Overview",
      content: sample_text,
      section_number: 1,
      tags: []
    )
  end

  let(:llm_tag_response) do
    {
      categories: ["Machine Learning", "Artificial Intelligence", "Computer Science"],
      content_tags: ["Neural Networks", "Deep Learning", "Computer Vision", "Natural Language Processing"]
    }.to_json
  end

  describe "#initialize" do
    it "creates service with default config" do
      expect(service.config[:max_retries]).to eq(3)
      expect(service.config[:timeout]).to eq(30)
      expect(service.config[:max_text_length]).to eq(200)
    end

    it "allows custom config" do
      custom_service = described_class.new({
        max_retries: 5,
        timeout: 45,
        max_text_length: 1000
      })

      expect(custom_service.config[:max_retries]).to eq(5)
      expect(custom_service.config[:timeout]).to eq(45)
      expect(custom_service.config[:max_text_length]).to eq(1000)
    end
  end

  describe "#generate_tags" do
    before do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_return(llm_tag_response)
    end

    it "generates tags for valid text" do
      result = service.generate_tags(sample_text, "AI Research")

      expect(result).to be_a(Hash)
      expect(result[:categories]).to be_an(Array)
      expect(result[:content_tags]).to be_an(Array)
      expect(service.smart_prompt_engine).to have_received(:call_worker).with(:analyze_content, { content: anything })
    end

    it "generates tags without topic" do
      result = service.generate_tags(sample_text)

      expect(result).to be_a(Hash)
      expect(result[:categories]).not_to be_empty
      expect(result[:content_tags]).not_to be_empty
    end

    it "supports multiple languages" do
      result = service.generate_tags(sample_text, "AI Research", [:zh_cn, :en])

      expect(result[:categories]).not_to be_empty
      expect(result[:content_tags]).not_to be_empty
    end

    it "truncates long text" do
      long_text = "A" * 500
      result = service.generate_tags(long_text)

      expect(service.smart_prompt_engine).to have_received(:call_worker).with(:analyze_content, { content: /A{200}\.\.\./ })
      expect(result).to be_a(Hash)
    end

    it "raises error for empty text" do
      expect { service.generate_tags("") }.to raise_error(ArgumentError, "Text cannot be empty")
      expect { service.generate_tags(nil) }.to raise_error(ArgumentError, "Text cannot be empty")
    end

    it "handles API errors with retry" do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_raise(StandardError.new("API Error"))

      expect { service.generate_tags(sample_text) }.to raise_error(SmartRAG::Errors::TagGenerationError)

      expect(service.smart_prompt_engine).to have_received(:call_worker).at_least(3).times
    end

    it "respects max tag limits" do
      result = service.generate_tags(
        sample_text,
        "AI Research",
        [:en],
        max_category_tags: 3,
        max_content_tags: 5
      )

      expect(result[:categories].size).to be <= 3
      expect(result[:content_tags].size).to be <= 5
    end

    it "handles malformed LLM response" do
      malformed_response = "Here are some tags: Machine Learning, AI, Deep Learning"
      allow(service.smart_prompt_engine).to receive(:call_worker).and_return(malformed_response)

      result = service.generate_tags(sample_text)

      expect(result).to be_a(Hash)
      expect(result[:categories]).to be_an(Array)
      expect(result[:content_tags]).to be_an(Array)
    end
  end

  describe "#batch_generate_tags" do
    let(:sections) do
      [
        instance_double("SmartRAG::Models::SourceSection", id: 1, section_title: "Section 1", content: "Content 1", section_number: 1),
        instance_double("SmartRAG::Models::SourceSection", id: 2, section_title: "Section 2", content: "Content 2", section_number: 2)
      ]
    end

    before do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_return(llm_tag_response)
    end

    it "generates tags for multiple sections" do
      results = service.batch_generate_tags(sections, "Topic")

      expect(results).to be_a(Hash)
      expect(results.keys).to contain_exactly(1, 2)
      expect(results[1]).to include(:categories, :content_tags)
      expect(results[2]).to include(:categories, :content_tags)
    end

    it "handles empty sections array" do
      results = service.batch_generate_tags([])
      expect(results).to eq({})
    end

    it "continues on individual section errors" do
      allow(service.smart_prompt_engine).to receive(:call_worker)
        .and_raise(StandardError.new("API Error"))

      results = service.batch_generate_tags(sections)

      expect(results[1]).to eq({ categories: [], content_tags: [] })
      expect(results[2]).to eq({ categories: [], content_tags: [] })
    end
  end

  describe "#find_or_create_tags" do
    before do
      allow(SmartRAG::Models::Tag).to receive(:find_or_create).and_call_original
    end

    it "finds or creates tags by name" do
      tag_names = ["Machine Learning", "AI", "Deep Learning"]
      tags = service.find_or_create_tags(tag_names)

      expect(tags.size).to eq(3)
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).exactly(3).times
    end

    it "handles parent-child relationships" do
      # Create a real tag for this test since we're testing database operations
      parent_tag = SmartRAG::Models::Tag.create!(name: "Technology_#{rand(1000)}")
      # Ensure we get the integer ID correctly
      parent_id_value = parent_tag.id.to_i  # Force to integer

      tags = service.find_or_create_tags(["AI_#{rand(1000)}"], parent_id_value)  # Pass as positional parameter

      expect(tags.first.parent_id).to eq(parent_id_value)
      expect(tags.first.name).to start_with("AI_")

      # Cleanup
      tags.each(&:destroy)
      parent_tag.destroy
    end

    it "cleans tag names" do
      tag_names = ["  Machine Learning!  ", "AI@2024", "  Deep_Learning  " ]
      service.find_or_create_tags(tag_names)

      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("Machine Learning", anything)
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("AI 2024", anything)
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("Deep_Learning", anything)
    end

    it "removes duplicates" do
      tag_names = ["AI", "Machine Learning", "AI", "Deep Learning", "Machine Learning"]
      tags = service.find_or_create_tags(tag_names)

      expect(tags.size).to eq(3)
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).exactly(3).times
    end

    it "returns empty array for empty input" do
      tags = service.find_or_create_tags([])
      expect(tags).to eq([])
    end
  end

  describe "#create_hierarchy" do
    it "creates hierarchical tag structure" do
      hierarchy = {
        "Technology" => {
          "AI" => ["Machine Learning", "Deep Learning"],
          "Web" => ["Frontend", "Backend"]
        }
      }

      allow(SmartRAG::Models::Tag).to receive(:find_or_create).and_call_original

      tags = service.create_hierarchy(hierarchy)

      expect(tags).not_to be_empty
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("Technology", parent_id: nil).once
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("AI", parent_id: anything).once
      expect(SmartRAG::Models::Tag).to have_received(:find_or_create).with("Machine Learning", parent_id: anything).once
    end

    it "handles nested hash structures" do
      hierarchy = {
        "Science" => {
          "Physics" => {
            "Quantum" => ["Entanglement", "Superposition"]
          }
        }
      }

      tags = service.create_hierarchy(hierarchy)

      expect(tags).not_to be_empty
      expect(tags.map(&:name)).to include("Science", "Physics", "Quantum", "Entanglement", "Superposition")
    end

    it "returns empty array for empty hierarchy" do
      tags = service.create_hierarchy({})
      expect(tags).to eq([])
    end
  end

  describe "#associate_with_section" do
    let(:tag1) { instance_double("SmartRAG::Models::Tag", id: 1, name: "AI") }
    let(:tag2) { instance_double("SmartRAG::Models::Tag", id: 2, name: "Machine Learning") }
    let(:section) { instance_double("SmartRAG::Models::SourceSection", id: 1, tags: []) }

    before do
      allow(section).to receive(:add_tag)
      allow(section).to receive(:tags).and_return([])
      allow(SmartRAG::Models::SectionTag).to receive(:find).and_return(double("SectionTag"))
      allow(section).to receive(:remove_all_tags)
    end

    it "associates tags with section" do
      service.associate_with_section(section, [tag1, tag2])

      expect(section).to have_received(:add_tag).with(tag1)
      expect(section).to have_received(:add_tag).with(tag2)
    end

    it "replaces existing tags when specified" do
      service.associate_with_section(section, [tag1], replace_existing: true)

      expect(section).to have_received(:remove_all_tags)
      expect(section).to have_received(:add_tag).with(tag1)
    end

    it "handles tag objects, IDs, and names" do
      allow(SmartRAG::Models::Tag).to receive(:find).and_return(tag1)

      expect { service.associate_with_section(section, [1, "AI", tag1]) }.not_to raise_error
    end
  end

  describe "#batch_associate_with_sections" do
    let(:section1) { instance_double("SmartRAG::Models::SourceSection", id: 1, tags: []) }
    let(:section2) { instance_double("SmartRAG::Models::SourceSection", id: 2, tags: []) }
    let(:tag1) { instance_double("SmartRAG::Models::Tag", id: 1, name: "AI") }
    let(:tag2) { instance_double("SmartRAG::Models::Tag", id: 2, name: "Machine Learning") }

    before do
      allow(section1).to receive(:add_tag)
      allow(section2).to receive(:add_tag)
      allow(SmartRAG::Models::SectionTag).to receive(:find).and_return(double("SectionTag"))
    end

    it "associates tags with multiple sections" do
      sections = [section1, section2]
      tags = [tag1, tag2]

      results = service.batch_associate_with_sections(sections, tags)

      expect(results).not_to be_empty
      expect(section1).to have_received(:add_tag).twice
      expect(section2).to have_received(:add_tag).twice
    end
  end

  describe "#dissociate_from_section" do
    let(:tag1) { instance_double("SmartRAG::Models::Tag", id: 1, name: "AI") }
    let(:tag2) { instance_double("SmartRAG::Models::Tag", id: 2, name: "Machine Learning") }
    let(:section) { instance_double("SmartRAG::Models::SourceSection", id: 1) }

    before do
      allow(section).to receive(:tags).and_return([tag1, tag2])
      allow(section).to receive(:remove_tag)
      allow(section).to receive(:remove_all_tags).and_return(2)
    end

    it "removes specific tags from section" do
      service.dissociate_from_section(section, [tag1])

      expect(section).to have_received(:remove_tag).with(tag1)
    end

    it "removes all tags when tags parameter is nil" do
      removed_count = service.dissociate_from_section(section, nil)

      expect(section).to have_received(:remove_all_tags)
      expect(removed_count).to eq(2)
    end
  end

  describe "#get_sections_by_tag" do
    let(:tag) { instance_double("SmartRAG::Models::Tag", id: 1, name: "AI") }
    let(:sections_dataset) { double("Sequel::Dataset") }
    let(:sections) { [instance_double("SmartRAG::Models::SourceSection", id: 1)] }

    before do
      allow(tag).to receive(:sections_dataset).and_return(sections_dataset)
      allow(sections_dataset).to receive(:where).and_return(sections_dataset)
      allow(sections_dataset).to receive(:association_join).and_return(sections_dataset)
      allow(sections_dataset).to receive(:limit).and_return(sections_dataset)
      allow(sections_dataset).to receive(:all).and_return(sections)
    end

    it "gets sections by tag" do
      result = service.get_sections_by_tag(tag)

      expect(result).to eq(sections)
    end

    it "filters by document ID" do
      service.get_sections_by_tag(tag, document_id: 5)

      expect(sections_dataset).to have_received(:where).with(document_id: 5)
    end

    it "filters by embedding presence" do
      service.get_sections_by_tag(tag, has_embedding: true)

      expect(sections_dataset).to have_received(:association_join).with(:embedding)
    end

    it "applies limit" do
      service.get_sections_by_tag(tag, limit: 10)

      expect(sections_dataset).to have_received(:limit).with(10)
    end
  end

  describe "#get_tags_for_section" do
    let(:section) { instance_double("SmartRAG::Models::SourceSection", id: 1) }
    let(:tag1) { instance_double("SmartRAG::Models::Tag", id: 1, ancestors: []) }
    let(:tag2) { instance_double("SmartRAG::Models::Tag", id: 2, ancestors: []) }

    before do
      allow(section).to receive(:tags).and_return([tag1, tag2])
    end

    it "gets tags for section" do
      tags = service.get_tags_for_section(section)

      expect(tags).to eq([tag1, tag2])
    end

    it "includes ancestor tags when specified" do
      ancestor_tag = instance_double("SmartRAG::Models::Tag", id: 3)
      allow(tag1).to receive(:ancestors).and_return([ancestor_tag])
      allow(tag2).to receive(:ancestors).and_return([])

      tags = service.get_tags_for_section(section, include_ancestors: true)

      expect(tags).to include(tag1, tag2, ancestor_tag)
    end
  end

  describe "#search_tags" do
    let(:tag1) { instance_double("SmartRAG::Models::Tag", id: 1, name: "Machine Learning") }
    let(:tag2) { instance_double("SmartRAG::Models::Tag", id: 2, name: "Deep Learning") }

    before do
      allow(SmartRAG::Models::Tag).to receive_message_chain(:where, :limit, :all).and_return([tag1, tag2])
    end

    it "searches tags by name" do
      tags = service.search_tags("learning")

      expect(tags).to eq([tag1, tag2])
    end

    it "respects limit option" do
      allow(SmartRAG::Models::Tag).to receive_message_chain(:where, :limit, :all).and_return([tag1])

      tags = service.search_tags("learning", limit: 1)

      expect(tags.size).to eq(1)
    end

    it "raises error for empty query" do
      expect { service.search_tags("") }.to raise_error(ArgumentError, "Query cannot be empty")
      expect { service.search_tags(nil) }.to raise_error(ArgumentError, "Query cannot be empty")
    end
  end

  describe "#get_popular_tags" do
    let(:popular_tags) do
      [
        { id: 1, name: "AI", usage_count: 100 },
        { id: 2, name: "Machine Learning", usage_count: 80 }
      ]
    end

    it "gets popular tags" do
      allow(SmartRAG::Models::Tag).to receive(:popular).with(limit: 20).and_return(popular_tags)

      result = service.get_popular_tags

      expect(result).to eq(popular_tags)
    end

    it "respects limit parameter" do
      allow(SmartRAG::Models::Tag).to receive(:popular).with(limit: 10).and_return(popular_tags[0..0])

      result = service.get_popular_tags(10)

      expect(result.size).to eq(1)
    end
  end

  describe "#get_tag_hierarchy" do
    let(:hierarchy) do
      [
        { id: 1, name: "Technology", children: [{ id: 2, name: "AI", children: [] }] }
      ]
    end

    it "gets tag hierarchy" do
      allow(SmartRAG::Models::Tag).to receive(:hierarchy).and_return(hierarchy)

      result = service.get_tag_hierarchy

      expect(result).to eq(hierarchy)
    end
  end
end
