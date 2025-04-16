# MCPEx

An Elixir client for the Model Context Protocol (MCP).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mcp_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mcp_ex, "~> 0.1.0"}
  ]
end
```

## Features

* Full MCP protocol implementation (version 2025-03-26)
* Multiple transport options (stdio, HTTP)
* Resource handling with subscriptions
* Tool invocation support
* Prompt template handling
* Shell environment integration

## Usage

```elixir
# Create a new client connected to a server via stdio
{:ok, client} = MCPEx.Client.start_link(
  transport: :stdio,
  command: "/path/to/server",
  capabilities: [:sampling, :roots]
)

# Or with HTTP transport
{:ok, client} = MCPEx.Client.start_link(
  transport: :http,
  url: "https://example.com/mcp",
  capabilities: [:sampling, :roots]
)

# List available resources
{:ok, %{resources: resources}} = MCPEx.Client.list_resources(client)

# Read a specific resource
{:ok, %{contents: contents}} = MCPEx.Client.read_resource(client, "file:///path/to/resource")

# Call a tool
{:ok, result} = MCPEx.Client.call_tool(client, "get_weather", %{location: "New York"})
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).