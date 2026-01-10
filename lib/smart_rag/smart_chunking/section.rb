module SmartRAG
  module SmartChunking
    Section = Struct.new(
      :title,
      :text,
      :level,
      :layout,
      keyword_init: true
    )
  end
end
