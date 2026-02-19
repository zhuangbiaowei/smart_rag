SmartPrompt.define_worker :get_embedding do
  # Use local Ollama by default for embedding generation.
  use "OllamaEmbedding"
  model ENV["EMBEDDING_MODEL"] || "qwen3-embedding"
  prompt params[:text]
  embeddings(1024)
end
