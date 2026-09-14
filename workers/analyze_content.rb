SmartPrompt.define_worker :analyze_content do
  # Use local Ollama by default for content analysis/tagging.
  # To use SiliconFlow instead, replace with:
  #   use "SiliconFlow"
  #   model "Qwen/Qwen3-8B"
  use "OllamaEmbedding"
  model ENV["LLM_MODEL"] || "qwen3"
  prompt params[:content]
  send_msg
end
