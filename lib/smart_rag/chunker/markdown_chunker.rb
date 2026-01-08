module SmartRAG
  module Chunker
    # MarkdownChunker splits markdown content into chunks based on headings
    class MarkdownChunker
      attr_reader :chunk_size, :overlap, :heading_levels

      # @param [Integer] chunk_size Target size for each chunk (in characters)
      # @param [Integer] overlap Overlap between chunks (in characters)
      # @param [Array<Integer>] heading_levels Which heading levels to split on (default: [1, 2, 3])
      def initialize(chunk_size: 2000, overlap: 200, heading_levels: [1, 2, 3])
        @chunk_size = chunk_size
        @overlap = overlap
        @heading_levels = heading_levels
      end

      # Split markdown content into chunks
      # @param [String] markdown_content Content to chunk
      # @return [Array<Hash>] Array of chunk hashes with :title and :content
      def chunk(markdown_content)
        return [] if markdown_content.nil? || markdown_content.empty?

        # First, try to split by headings
        heading_chunks = split_by_headings(markdown_content)

        # If we have heading-based chunks with actual headings, use them
        # Otherwise, fall back to size-based splitting
        if heading_chunks.length > 0 && heading_chunks.first[:title]
          # Further split large heading chunks by size
          result = []
          heading_chunks.each do |chunk|
            if chunk[:content].length > chunk_size * 1.5
              # Split large chunk further
              sub_chunks = split_large_chunk(chunk)
              result.concat(sub_chunks)
            else
              result << chunk
            end
          end
          result
        else
          # No headings found, use size-based splitting
          split_by_size(markdown_content)
        end
      end

      private

      # Split content by markdown headings - Handles nested headings properly
      def split_by_headings(content)
        chunks = []
        lines = content.lines
        return chunks if lines.empty?

        # Check if we have any headings
        heading_pattern = /^(#{@heading_levels.map { |l| '#' * l }.join('|')})\s+(.+)$/

        # Find all heading positions first
        heading_positions = []
        lines.each_with_index do |line, idx|
          if line.match?(heading_pattern)
            heading_positions << idx
          end
        end

        # If no headings, use fallback to size-based splitting
        if heading_positions.empty?
          cleaned = clean_chunk_content(content)
          return cleaned.length > 10 ? [{ title: nil, content: cleaned }] : []
        end

        # Build chunks based on heading hierarchy
        # Split at any heading that matches our configured heading levels
        current_chunk_start = nil
        current_chunk_title = nil
        first_h1_processed = false
        first_h1_title = nil
        first_h1_skipped = false
        intro_lines = []
        intro_text = nil
        intro_pending = false

        lines.each_with_index do |line, idx|
          # Check if this line is a heading
          if (match = line.match(heading_pattern))
            heading_level = match[1].length
            heading_title = match[2].strip

            # Handle the very first line - if it's h1, note it as potential document title
            if idx == 0 && heading_level == 1
              first_h1_title = heading_title
              first_h1_processed = true
              first_h1_skipped = true
              next
            end

            # Check if this heading level should create a chunk
            if @heading_levels.include?(heading_level) && !(idx == 0 && heading_level == 1)
              # Save previous chunk if it exists
              if current_chunk_start && current_chunk_title
                # Extract content from start of this section to current line
                content_lines = lines[current_chunk_start...idx]
                if content_lines && content_lines.length > 1
                  # Remove the heading line
                  section_content = clean_chunk_content(content_lines[1..-1].join)
                  if intro_pending && intro_text && section_content.length > 0
                    section_content = [intro_text, section_content].join("\n\n")
                    intro_pending = false
                  elsif intro_pending && intro_text && section_content.empty?
                    section_content = intro_text
                    intro_pending = false
                  end
                  if section_content.length > 0
                    chunks << { title: current_chunk_title, content: section_content }
                  end
                end
              end

              if first_h1_skipped && current_chunk_start.nil? && intro_text.nil?
                cleaned_intro = clean_chunk_content(intro_lines.join)
                if cleaned_intro.length > 0
                  intro_text = cleaned_intro
                  intro_pending = true
                end
              end

              # Start new chunk
              current_chunk_start = idx
              current_chunk_title = heading_title
            end
          elsif first_h1_skipped && current_chunk_start.nil?
            intro_lines << line
          end
        end

        # Save the last chunk
        if current_chunk_start && current_chunk_title
          end_idx = heading_positions[heading_positions.index(current_chunk_start) + 1] || lines.length
          content_lines = lines[current_chunk_start...end_idx]
          if content_lines && content_lines.length > 1
            section_content = clean_chunk_content(content_lines[1..-1].join)
            if intro_pending && intro_text && section_content.length > 0
              section_content = [intro_text, section_content].join("\n\n")
              intro_pending = false
            elsif intro_pending && intro_text && section_content.empty?
              section_content = intro_text
              intro_pending = false
            end
            if section_content.length > 0
              chunks << { title: current_chunk_title, content: section_content }
            end
          end
        end

        # If we skipped the first h1 as a document title but no chunks were created,
        # go back and create a chunk for it
        if first_h1_skipped && chunks.empty? && first_h1_title
          # Get content after the first h1
          if lines.length > 1
            content_after_h1 = lines[1..-1].join
            cleaned_content = clean_chunk_content(content_after_h1)
            if cleaned_content.length > 0
              chunks << { title: first_h1_title, content: cleaned_content }
            end
          end
        end

        chunks
      end

      # Clean chunk content by removing heading lines
      def clean_chunk_content(content)
        return "" if content.nil? || content.empty?

        content = content.strip
        return "" if content.empty?

        lines = content.lines

        # Remove leading heading lines
        while lines.first && lines.first =~ /^#+\s+/
          lines.shift
        end

        result = lines.join.strip
        result
      end

      # SPLIT_CONTENT

      # Split content by size without considering headings
      def split_by_size(content)
        chunks = []
        return chunks if content.nil? || content.empty?

        position = 0
        chunk_index = 0
        content_length = content.length

        while position < content_length
          # Calculate the end position for this chunk
          end_pos = [position + chunk_size, content_length].min

          # Look backward for a sentence boundary if we're not at the end
          if end_pos < content_length
            # Search backward for a sentence boundary (., !, ?)
            search_start = end_pos
            search_end = [position + chunk_size * 0.8, content_length].min # Don't look too far back

            (search_start - 1).downto(search_end.to_i) do |i|
              if content[i] =~ /[.!?]/
                # Found a sentence boundary
                # Make sure it's followed by whitespace or end of content
                if i + 1 >= content_length || content[i + 1] =~ /\s/
                  end_pos = i + 1
                  break
                end
              end
            end
          end

          # Extract the chunk
          chunk_content = content[position...end_pos].strip

          if chunk_content.length > 50
            chunks << {
              title: generate_chunk_title(chunk_content, chunk_index),
              content: chunk_content
            }
            chunk_index += 1
          end

          # Move position forward, keeping overlap
          next_position = end_pos
          if next_position < content_length
            # Add overlap
            overlap_chars = [overlap, chunk_content.length].min
            position = [next_position - overlap_chars, position + 50].max # Don't overlap too much
          else
            position = content_length
          end
        end

        chunks
      end

      # Split a large chunk that exceeded size limits
      def split_large_chunk(chunk)
        # Use the heading as title and split the content
        sub_chunks = split_by_size(chunk[:content])

        # Prepend the original heading to each sub-chunk
        sub_chunks.each_with_index do |sub_chunk, i|
          sub_chunk[:title] = if i == 0
                                chunk[:title]
                              else
                                "#{chunk[:title]} (Part #{i + 1})"
                              end
        end

        sub_chunks
      end

      # Generate a title for a chunk based on its content
      def generate_chunk_title(content, index)
        return nil if content.nil? || content.empty?

        # Try to extract first heading (if present)
        lines = content.strip.lines
        lines.each do |line|
          if line =~ /^#+\s+(.+)$/
            return $1.strip
          end
        end

        # Use first sentence
        first_line = lines.first&.strip
        if first_line && first_line =~ /^(.*?[.!?])/
          sentence = $1.strip
          return sentence.length > 100 ? sentence[0...100] + '...' : sentence
        elsif first_line && !first_line.empty?
          # Just use first line (without period)
          return first_line.length > 100 ? first_line[0...100] + '...' : first_line
        end

        # Fallback to chunk number
        "Section #{index + 1}"
      end
    end
  end

  # Monkey-patch String to add reverse match method
  class ::String
    # Find last match of pattern in string
    # @param [Regexp] pattern Pattern to match
    # @param [Integer] start_pos Position to start searching from (default: end of string)
    # @return [MatchData] Last match or nil
    def rmatch(pattern, start_pos = nil)
      start_pos ||= length
      start_pos = length + start_pos if start_pos < 0
      start_pos = length if start_pos > length

      # Search backwards from start_pos
      (0..start_pos).reverse_each do |i|
        # Try to match at position i
        substring = self[i...length]
        match = pattern.match(substring)
        return match if match
      end
      nil
    rescue
      nil
    end
  end
end
