import Config

# Configuration for the MCPEx application
config :mcp_ex,
  protocol_version: "2025-03-26"

# Import environment specific config
import_config "#{config_env()}.exs"