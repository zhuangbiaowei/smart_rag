require 'spec_helper'
require 'tempfile'
require_relative '../../lib/smart_rag/core/document_processor'

RSpec.describe SmartRAG::Core::DocumentProcessor do
  let(:config) { { logger: Logger.new('/dev/null') } }
  let(:processor) { described_class.new(config) }

  describe '#initialize' do
    it 'accepts configuration' do
      expect(processor.config).to eq(config)
    end

    it 'uses default values' do
      default_processor = described_class.new
      expect(default_processor.config[:logger]).to be_a(Logger)
    end
  end

  describe '#download_from_url' do
    let(:temp_file) { Tempfile.new(['test', '.html']) }
    let(:url) { 'http://example.com/document.html' }

    before do
      # Mock Net::HTTP
      response = double('response')
      allow(response).to receive(:code).and_return('200')
      allow(response).to receive(:body).and_return('<html><body>Test content</body></html>')

      http = double('http')
      allow(http).to receive(:request).and_return(response)

      allow(Net::HTTP).to receive(:start).and_yield(http)
    end

    after do
      temp_file.close
      temp_file.unlink
    end

    it 'downloads content from URL' do
      file_path = processor.download_from_url(url)

      expect(File.exist?(file_path)).to be true
      content = File.read(file_path)
      expect(content).to include('Test content')

      # Clean up
      File.delete(file_path) if File.exist?(file_path)
    end

    it 'follows redirects' do
      redirect_response = double('redirect_response')
      allow(redirect_response).to receive(:code).and_return('302')
      allow(redirect_response).to receive(:[]).with('Location').and_return('http://example.com/redirected.html')

      success_response = double('success_response')
      allow(success_response).to receive(:code).and_return('200')
      allow(success_response).to receive(:body).and_return('<html><body>Redirected content</body></html>')

      http = double('http')
      allow(http).to receive(:request).and_return(redirect_response, success_response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      file_path = processor.download_from_url(url)

      expect(File.exist?(file_path)).to be true
      expect(File.read(file_path)).to include('Redirected content')
      File.delete(file_path) if File.exist?(file_path)
    end

    it 'handles download errors' do
      response = double('response')
      allow(response).to receive(:code).and_return('404')
      allow(response).to receive(:message).and_return('Not Found')

      http = double('http')
      allow(http).to receive(:request).and_return(response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { processor.download_from_url(url) }.to raise_error(/HTTP Error: 404/)
    end
  end

  describe '#extract_metadata' do
    let(:temp_file) { Tempfile.new(['test', '.html']) }

    before do
      temp_file.write('<html><head><title>Test Document</title><meta name="author" content="Test Author"></head><body>Content</body></html>')
      temp_file.close
    end

    after do
      temp_file.unlink
    end

    it 'extracts basic file metadata' do
      metadata = processor.extract_metadata(temp_file.path)

      expect(metadata[:file_path]).to eq(temp_file.path)
      expect(metadata[:file_size]).to be > 0
      expect(metadata[:file_type]).to eq('.html')
      expect(metadata).to have_key(:created_at)
      expect(metadata).to have_key(:modified_at)
    end

    it 'extracts HTML metadata' do
      metadata = processor.extract_metadata(temp_file.path)

      expect(metadata[:title]).to eq('Test Document')
      expect(metadata[:author]).to eq('Test Author')
    end

    it 'merges custom metadata' do
      custom_metadata = { title: 'Custom Title', custom_field: 'custom value' }
      metadata = processor.extract_metadata(temp_file.path, metadata: custom_metadata)

      expect(metadata[:title]).to eq('Custom Title') # Overridden
      expect(metadata[:custom_field]).to eq('custom value')
    end
  end

  describe '#detect_language' do
    it 'detects English' do
      expect(processor.detect_language('This is English text')).to eq('en')
    end

    it 'detects Chinese' do
      expect(processor.detect_language('这是中文文本')).to eq('zh')
    end

    it 'detects Japanese' do
      expect(processor.detect_language('これは日本語のテキストです')).to eq('ja')
    end

    it 'detects Korean' do
      expect(processor.detect_language('이것은 한국어 텍스트입니다')).to eq('ko')
    end

    it 'defaults to English for empty text' do
      expect(processor.detect_language('')).to eq('en')
    end

    it 'defaults to English for mixed content' do
      expect(processor.detect_language('Text with 123 and symbols !@#')).to eq('en')
    end
  end

  describe '#chunk_content' do
    let(:markdown_content) do
      <<~MARKDOWN
        # Main Title

        ## Section 1

        Content for section 1.

        ## Section 2

        Content for section 2.
      MARKDOWN
    end

    it 'chunks markdown content' do
      chunks = processor.chunk_content(markdown_content, chunk_size: 1000, overlap: 100)

      expect(chunks).to be_an(Array)
      expect(chunks.length).to be > 0

      chunks.each do |chunk|
        expect(chunk).to have_key(:title)
        expect(chunk).to have_key(:content)
      end
    end
  end
end
