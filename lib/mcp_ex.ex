defmodule MCPEx do
  @moduledoc """
  MCPEx is an Elixir client library for the Model Context Protocol (MCP).

  This library provides a complete, spec-compliant implementation of the
  Model Context Protocol (MCP) client, supporting version 2025-03-26 of the specification.

  ## Features

  * Full protocol implementation with capability negotiation
  * Multiple transport options (stdio, HTTP)
  * Resource handling with subscriptions
  * Tool invocation support
  * Prompt template handling
  * Shell environment integration
  """

  @doc """
  Returns the current MCP protocol version supported by this library.
  """
  def protocol_version do
    "2025-03-26"
  end
end