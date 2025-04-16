ExUnit.start()

# Ensure the scripts directory exists and is executable
scripts_path = Application.get_env(:mcp_ex, :test)[:scripts_path]
if scripts_path do
  File.mkdir_p!(scripts_path)
  
  # Check for and make the wrapper script executable
  wrapper_path = Path.join(scripts_path, "wrapper.sh")
  if File.exists?(wrapper_path) do
    File.chmod!(wrapper_path, 0o755)
  end
end