require "spec_helper"
require "smart_rag/services/embedding_service"

RSpec.describe SmartRAG::Services::EmbeddingService do
  let(:config) { { config_path: "config/llm_config.yml", batch_size: 2 } }
  let(:service) { described_class.new(config) }

  let(:section) do
    instance_double(
      "SmartRAG::Models::SourceSection",
      id: 1,
      section_title: "Test Section",
      content: "This is test content",
      section_number: 1
    )
  end

  let(:embedding_response) do
    Array.new(1024) { rand(0.0..1.0) }
  end

  describe "#initialize" do
    it "creates service with default config" do
      expect(service.config[:retries]).to eq(3)
      expect(service.config[:timeout]).to eq(60)
      expect(service.config[:batch_size]).to eq(2)
    end

    it "allows custom config" do
      custom_service = described_class.new({
        retries: 5,
        batch_size: 10
      })

      expect(custom_service.config[:retries]).to eq(5)
      expect(custom_service.config[:batch_size]).to eq(10)
    end
  end

  describe "#generate_for_section" do
    before do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_return(embedding_response)
      allow(SmartRAG::Models::Embedding).to receive(:new).and_call_original
      allow_any_instance_of(SmartRAG::Models::Embedding).to receive(:save!).and_return(true)
      allow_any_instance_of(SmartRAG::Models::Embedding).to receive(:id).and_return(1)
    end

    it "generates embedding for a valid section" do
      result = service.generate_for_section(section)

      expect(result).to be_a(SmartRAG::Models::Embedding)
      expect(result.source_id).to eq(1)
      expect(service.smart_prompt_engine).to have_received(:call_worker).with(:get_embedding, { text: "Title: Test Section\n\nSection: 1\n\nThis is test content" })
    end

    it "raises error for nil section" do
      expect { service.generate_for_section(nil) }.to raise_error(ArgumentError, "Section cannot be nil")
    end

    it "raises error for empty content" do
      empty_section = instance_double("SmartRAG::Models::SourceSection", content: "")
      expect { service.generate_for_section(empty_section) }.to raise_error(ArgumentError, "Section content cannot be empty")
    end

    it "handles API errors with retry" do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_raise(StandardError.new("API Error"))

      expect { service.generate_for_section(section) }.to raise_error(StandardError, /API Error/)

      expect(service.smart_prompt_engine).to have_received(:call_worker).exactly(3).times
    end

    it "generates embedding with custom options" do
      service.generate_for_section(section, { model: "text-embedding-3-small" })

      expect(service.smart_prompt_engine).to have_received(:call_worker)
    end
  end

  describe "#batch_generate" do
    let(:sections) do
      [
        instance_double("SmartRAG::Models::SourceSection", id: 1, section_title: "Section 1", content: "Content 1", section_number: 1),
        instance_double("SmartRAG::Models::SourceSection", id: 2, section_title: "Section 2", content: "Content 2", section_number: 2),
        instance_double("SmartRAG::Models::SourceSection", id: 3, section_title: "Section 3", content: "Content 3", section_number: 3)
      ]
    end

    let(:batch_embedding_response) do
      [
        Array.new(1024) { rand(0.0..1.0) },
        Array.new(1024) { rand(0.0..1.0) },
        Array.new(1024) { rand(0.0..1.0) }
      ]
    end

    before do
      allow(service.smart_prompt_engine).to receive(:call_worker) do |_, params|
        # Return embedding based on text content
        Array.new(1024) { rand(0.0..1.0) }
      end
      allow(SmartRAG::Models::Embedding).to receive(:batch_insert).and_return(true)
      allow(SmartRAG::Models::Embedding).to receive(:by_sections).and_return([])
    end

    it "processes sections in batches" do
      expect(SmartRAG::Models::Embedding).to receive(:batch_insert).twice
      expect(SmartRAG::Models::Embedding).to receive(:by_sections).twice.and_return([])

      result = service.batch_generate(sections)
      expect(result).to eq([])
    end

    it "handles empty array" do
      result = service.batch_generate([])
      expect(result).to eq([])
    end

    it "raises error for nil sections" do
      expect { service.batch_generate(nil) }.to raise_error(ArgumentError, "Sections array cannot be nil")
    end

    it "falls back to individual generation on batch failure" do
      allow(SmartRAG::Models::Embedding).to receive(:batch_insert).and_raise(StandardError.new("Batch failed"))
      allow(service).to receive(:generate_for_section).and_return(instance_double("SmartRAG::Models::Embedding"))

      results = service.batch_generate(sections[0..1])

      expect(service).to have_received(:generate_for_section).twice
    end
  end

  describe "#delete_by_section" do
    before do
      allow(SmartRAG::Models::Embedding).to receive(:delete_by_section).and_return(2)
    end

    it "deletes embeddings for a section" do
      result = service.delete_by_section(section)
      expect(result).to eq(2)
    end

    it "raises error for nil section" do
      expect { service.delete_by_section(nil) }.to raise_error(ArgumentError, "Section cannot be nil")
    end
  end

  describe "#update_embedding" do
    let(:embedding) { instance_double("SmartRAG::Models::Embedding", id: 1) }
    let(:section) { instance_double("SmartRAG::Models::SourceSection", id: 1, content: "Updated content") }

    before do
      allow(embedding).to receive(:section).and_return(section)
      allow(embedding).to receive(:update).and_return(true)
      allow(service.smart_prompt_engine).to receive(:call_worker).and_return(embedding_response)
    end

    it "updates existing embedding" do
      result = service.update_embedding(embedding)
      expect(result).to eq(embedding)
    end

    it "raises error for nil embedding" do
      expect { service.update_embedding(nil) }.to raise_error(ArgumentError, "Embedding cannot be nil")
    end
  end

  describe "retry logic" do
    it "retries on timeout" do
      allow(service.smart_prompt_engine).to receive(:call_worker).and_raise(Timeout::Error)

      expect { service.generate_for_section(section) }.to raise_error(StandardError, /Timeout::Error/)
      expect(service.smart_prompt_engine).to have_received(:call_worker).exactly(3).times
    end

    it "uses exponential backoff" do
      attempts = 0
      allow(service.smart_prompt_engine).to receive(:call_worker) do
        attempts += 1
        raise "Error" if attempts < 3
        embedding_response
      end
      allow_any_instance_of(SmartRAG::Models::Embedding).to receive(:save!).and_return(true)
      allow_any_instance_of(SmartRAG::Models::Embedding).to receive(:id).and_return(1)

      result = service.generate_for_section(section)

      expect(attempts).to eq(3)
      expect(result).to be_a(SmartRAG::Models::Embedding)
    end
  end
end
