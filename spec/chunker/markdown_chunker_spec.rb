require 'spec_helper'
require_relative '../../lib/smart_rag/chunker/markdown_chunker'

RSpec.describe SmartRAG::Chunker::MarkdownChunker do
  let(:chunker) { described_class.new }

  describe '#chunk' do
    context 'with simple markdown content' do
      let(:content) do
        <<~MARKDOWN
          # Main Title

          This is the introduction paragraph.

          ## Section 1

          Content for section 1 with more text to make it longer. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

          ## Section 2

          Content for section 2 with more text to make it longer. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
        MARKDOWN
      end

      it 'splits content by headings' do
        chunks = chunker.chunk(content)

        expect(chunks).to be_an(Array)
        expect(chunks.length).to eq(2)

        expect(chunks[0][:title]).to eq('Section 1')
        expect(chunks[0][:content]).to include('Content for section 1')

        expect(chunks[1][:title]).to eq('Section 2')
        expect(chunks[1][:content]).to include('Content for section 2')
      end
    end

    context 'with nested headings' do
      let(:content) do
        <<~MARKDOWN
          # Main Title

          ## Section 1

          Content for section 1.

          ### Subsection 1.1

          Content for subsection 1.1

          ### Subsection 1.2

          Content for subsection 1.2

          ## Section 2

          Content for section 2
        MARKDOWN
      end

      it 'splits by specified heading levels' do
        # By default, should split by h1, h2, h3
        chunks = chunker.chunk(content)

        expect(chunks.length).to be >= 3
        expect(chunks.any? { |c| c[:title] == 'Section 1' }).to be true
        expect(chunks.any? { |c| c[:title] == 'Subsection 1.1' }).to be true
      end

      it 'can be configured to split only by h1 and h2' do
        chunker_h2 = described_class.new(heading_levels: [1, 2])
        chunks = chunker_h2.chunk(content)

        # Should not have subsection titles
        expect(chunks.any? { |c| c[:title] == 'Subsection 1.1' }).to be false
        expect(chunks.any? { |c| c[:title] == 'Section 1' }).to be true
      end
    end

    context 'with very long sections' do
      let(:content) do
        # Create a section with very long content
        long_paragraph = 'This is a long paragraph. ' * 200
        <<~MARKDOWN
          # Short Title

          ## Very Long Section

          #{long_paragraph}
        MARKDOWN
      end

      it 'splits long sections by size' do
        chunks = chunker.chunk(content)

        # Should split the long section into multiple chunks
        expect(chunks.length).to be > 1

        # Each chunk should have a reasonable size
        chunks.each do |chunk|
          expect(chunk[:content].length).to be <= chunker.chunk_size * 1.5
        end
      end

      it 'maintains section title for sub-chunks' do
        chunks = chunker.chunk(content)

        # First chunk should have the original title
        expect(chunks[0][:title]).to eq('Very Long Section')

        # Subsequent chunks should have "(Part N)"
        if chunks.length > 1
          expect(chunks[1][:title]).to match(/Part 2/)
        end
      end
    end

    context 'with content without headings' do
      let(:content) do
        # Create content without any markdown headings
        paragraphs = []
        5.times do |i|
          paragraphs << "This is paragraph #{i + 1}. " * 50
        end
        paragraphs.join("\n\n")
      end

      it 'falls back to size-based splitting' do
        chunks = chunker.chunk(content)

        expect(chunks).to be_an(Array)
        expect(chunks.length).to be > 1

        # Should have generated titles
        expect(chunks.first[:title]).not_to be_nil
      end

      it 'splits at sentence boundaries when possible' do
        chunks = chunker.chunk(content)

        # Check if chunks end at sentence boundaries (most of them)
        sentence_boundaries = chunks.count do |chunk|
          content = chunk[:content].strip
          content.end_with?('.') || content.end_with?('!') || content.end_with?('?')
        end

        # At least 70% should end at sentence boundaries
        expect(sentence_boundaries.to_f / chunks.length).to be >= 0.7
      end
    end

    context 'with empty content' do
      it 'returns empty array for nil' do
        expect(chunker.chunk(nil)).to eq([])
      end

      it 'returns empty array for empty string' do
        expect(chunker.chunk('')).to eq([])
      end
    end

    context 'with very short content' do
      let(:content) do
        <<~MARKDOWN
          # Short

          Very short.
        MARKDOWN
      end

      it 'returns single chunk' do
        chunks = chunker.chunk(content)

        expect(chunks.length).to eq(1)
        expect(chunks[0][:content]).to include('Very short')
      end
    end

    context 'with custom chunk size and overlap' do
      let(:long_content) do
        # Create content longer than default chunk size
        'This is a sentence. ' * 500
      end

      it 'respects custom chunk size' do
        custom_chunker = described_class.new(chunk_size: 1000, overlap: 100)
        chunks = custom_chunker.chunk(long_content)

        chunks.each do |chunk|
          expect(chunk[:content].length).to be <= 1500  # Allow some margin
        end
      end

      it 'creates overlapping chunks' do
        custom_chunker = described_class.new(chunk_size: 500, overlap: 200)
        chunks = custom_chunker.chunk(long_content)

        expect(chunks.length).to be > 2

        # Check overlap between consecutive chunks
        (0...chunks.length - 1).each do |i|
          current_end = chunks[i][:content][-200..-1]
          next_start = chunks[i + 1][:content][0..200]

          # Should have some overlap
          overlap = current_end.split & next_start.split
          expect(overlap.length).to be > 0
        end
      end
    end

    context 'with special characters' do
      let(:content) do
        <<~MARKDOWN
          # Special Characters

          This section has special characters:
          - Emojis: 😀😍🎉
          - Chinese: 中文测试
          - Japanese: 日本語テスト
          - Korean: 한국어테스트
          - Code: `code block`
          - Math: $E=mc^2$
        MARKDOWN
      end

      it 'handles special characters correctly' do
        chunks = chunker.chunk(content)

        expect(chunks).not_to be_empty
        expect(chunks[0][:content]).to include('😀')
        expect(chunks[0][:content]).to include('中文')
        expect(chunks[0][:content]).to include('日本語')
        expect(chunks[0][:content]).to include('한국어')
      end
    end

    context 'with code blocks' do
      let(:content) do
        <<~MARKDOWN
          # Code Example

          Here's some code:

          ```ruby
          def hello
            puts "Hello, world!"
          end
          ```

          More text here.
        MARKDOWN
      end

      it 'preserves code blocks in chunks' do
        chunks = chunker.chunk(content)

        expect(chunks[0][:content]).to include('```ruby')
        expect(chunks[0][:content]).to include('def hello')
        expect(chunks[0][:content]).to include('```')
      end
    end
  end
end
