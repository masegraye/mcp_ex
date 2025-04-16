import Config

# Test-specific configuration
config :logger, level: :debug

# Configure paths for test resources
config :mcp_ex, :test,
  scripts_path: Path.join(Path.dirname(__DIR__), "priv/scripts")