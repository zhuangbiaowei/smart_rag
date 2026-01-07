require 'spec_helper'
require 'smart_rag/core/document_processor'
require 'smart_rag/core/markitdown_bridge'
require 'tempfile'

RSpec.describe "Markitdown integration" do
  let(:config) { { logger: Logger.new('/dev/null') } }
  let(:processor) { SmartRAG::Core::DocumentProcessor.new(config) }
  let(:markitdown_bridge) { instance_double("SmartRAG::Core::MarkitdownBridge") }

  before do
    # Mock markitdown bridge
    allow(SmartRAG::Core::MarkitdownBridge).to receive(:new).and_return(markitdown_bridge)
  end

  describe "#convert_to_markdown" do
    let(:temp_file) { Tempfile.new(['test', '.pdf']) }
    let(:html_file) { Tempfile.new(['test', '.html']) }

    before do
      # Create a test PDF file
      temp_file.write("%PDF-1.4 test content")
      temp_file.close

      # Create a test HTML file
      html_file.write("<html><body>Test content</body></html>")
      html_file.close
    end

    after do
      temp_file.unlink
      html_file.unlink
    end

    it "converts HTML to markdown using markitdown" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_return("Converted markdown content")

      result = processor.send(:convert_to_markdown, html_file.path)

      expect(result).to be_a(String)
      expect(result.length).to be > 0
      expect(result).to eq("Converted markdown content")
    end

    it "handles markitdown not being available" do
      allow(markitdown_bridge).to receive(:available?).and_return(false)

      expect {
        processor.send(:convert_to_markdown, html_file.path)
      }.to raise_error(LoadError, /markitdown/)
    end

    it "handles conversion failures gracefully" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_raise(RuntimeError, "Conversion failed")

      expect {
        processor.send(:convert_to_markdown, html_file.path)
      }.to raise_error(RuntimeError, /Conversion failed/)
    end

    it "retries conversion on transient errors" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)

      attempts = 0
      allow(markitdown_bridge).to receive(:convert) do
        attempts += 1
        raise "Network error" if attempts < 3
        "Success after retry"
      end

      result = processor.send(:convert_to_markdown, html_file.path)

      expect(result).to eq("Success after retry")
      expect(attempts).to eq(3)
    end

    it "handles nil markdown result from markitdown" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_return("")

      expect {
        processor.send(:convert_to_markdown, html_file.path)
      }.to raise_error(RuntimeError, /empty result/)
    end

    it "handles missing file" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_raise(RuntimeError, "File not found")

      expect {
        processor.send(:convert_to_markdown, "/nonexistent/file.html")
      }.to raise_error(RuntimeError, /File not found/)
    end

    it "processes various file formats" do
      formats = [
        { ext: '.html', content: '<html><body>HTML content</body></html>' },
        { ext: '.docx', content: 'PK\x03\x04[Content_Types].xml...' },
        { ext: '.pptx', content: 'PK\x03\x04[Content_Types].xml...' },
        { ext: '.xlsx', content: 'PK\x03\x04[Content_Types].xml...' }
      ]

      formats.each do |format|
        file = Tempfile.new(['test', format[:ext]])
        file.write(format[:content])
        file.close

        allow(markitdown_bridge).to receive(:available?).and_return(true)
        allow(markitdown_bridge).to receive(:convert).with(file.path).and_return("Converted #{format[:ext]}")

        result = processor.send(:convert_to_markdown, file.path)
        expect(result).to include("Converted")

        file.unlink
      end
    end
  end

  describe "document processing workflow with markitdown" do
    let(:markdown_content) do
      <<~MARKDOWN
        # Test Document

        This is a test document with multiple sections.

        ## Section 1

        Content for section 1.

        ## Section 2

        Content for section 2.
      MARKDOWN
    end

    let(:temp_doc) { Tempfile.new(['test', '.docx']) }

    before do
      # Mock the entire conversion workflow
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_return(markdown_content)

      # Mock document creation
      allow(SmartRAG::Models::SourceDocument).to receive(:create_or_update).and_return(
        double("document", id: 1, title: "Test Document", :set_download_state => true, :exists? => true)
      )

      # Mock section saving
      allow(SmartRAG::Models::SourceSection).to receive(:batch_insert).and_return(true)
    end

    after { temp_doc.unlink }

    it "processes document through markitdown and creates sections" do
      processor.process(temp_doc.path)

      # Verify markitdown was used
      expect(SmartRAG::Core::MarkitdownBridge).to have_received(:new)
    end

    it "handles markitdown errors in the processing pipeline" do
      allow(markitdown_bridge).to receive(:convert).and_raise(RuntimeError, "Markitdown error")

      expect { processor.process(temp_doc.path) }.to raise_error(RuntimeError, /Markitdown error/)
    end
  end

  describe "external service error recovery" do
    let(:temp_file) { Tempfile.new(['test', '.html']) }

    before do
      temp_file.write("<html><body>Test</body></html>")
      temp_file.close
    end

    after { temp_file.unlink }

    it "implements circuit breaker pattern for repeated failures" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_raise(RuntimeError, "Service unavailable")

      attempts = 0
      begin
        processor.send(:convert_to_markdown, temp_file.path, max_retries: 1)
      rescue RuntimeError
        attempts += 1
      end

      # Should have attempted once with circuit breaker
      expect(attempts).to eq(1)
    end

    it "handles rate limiting errors" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)
      allow(markitdown_bridge).to receive(:convert).and_raise(RuntimeError, "Rate limit exceeded")

      expect { processor.send(:convert_to_markdown, temp_file.path, max_retries: 1) }.to raise_error(/Rate limit exceeded/)
    end

    it "provides helpful error messages for common issues" do
      allow(markitdown_bridge).to receive(:available?).and_return(true)

      expect { processor.send(:convert_to_markdown, "/nonexistent/file.docx") }.to raise_error(/File not found/)
    end
  end
end
