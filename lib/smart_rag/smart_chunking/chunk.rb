module SmartRAG
  module SmartChunking
    Chunk = Struct.new(
      :title,
      :content,
      :metadata,
      keyword_init: true
    )
  end
end
