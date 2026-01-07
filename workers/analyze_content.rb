SmartPrompt.define_worker :analyze_content do
  use "SiliconFlow"
  model "Qwen/Qwen3-8B"
  prompt params[:content]
  send_msg
end
