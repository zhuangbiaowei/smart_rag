SmartPrompt.define_worker :get_embedding do
  # Use local Ollama by default for embedding generation.
  use "OllamaEmbedding"
  model ENV["EMBEDDING_MODEL"] || "qwen3-embedding"
  prompt params[:text]
  embeddings(ENV.fetch("EMBEDDING_DIMENSIONS", "4096").to_i)
end
