#!/usr/bin/env ruby
# Quick patch script to fix the language detection issue

file_path = '/root/smart_rag/lib/smart_rag/services/hybrid_search_service.rb'
content = File.read(file_path)

# Find and replace the problematic line
# We want to add debug logging before the language line
old_text = '          @logger.info "Hybrid search: \'#{query}\', language: #{language}, limit: #{limit}, alpha: #{alpha}"'

if content.include?(old_text)
  puts 'Found the text to replace!'

  # Check if debug log is already there
  debug_text = '          @logger.debug "HybridSearchService: language=#{language} (type: #{language.class}), options[:language]=#{options[:language].inspect}"'

  if !content.include?(debug_text)
    puts 'Adding debug log...'
    new_content = content.sub(old_text, debug_text + "\n" + old_text)
    File.write(file_path, new_content)
    puts 'Done! Debug log added.'
  else
    puts 'Debug log already exists.'
  end
else
  puts 'Could not find the target text!'
end
