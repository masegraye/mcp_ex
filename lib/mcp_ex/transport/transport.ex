defmodule MCPEx.Transport do
  @moduledoc """
  Defines the behavior for MCP transport implementations.

  The transport layer handles the communication between the client and server,
  providing abstraction over different transport mechanisms (stdio, HTTP, etc.).
  """

  @doc """
  Creates a new transport instance.

  ## Parameters

  * `transport_type` - The type of transport to create (:stdio, :http, :test)
  * `options` - Options specific to the transport type

  ## Returns

  * `{:ok, pid}` - The transport was created successfully
  * `{:error, reason}` - Failed to create the transport
  """
  @spec create(atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def create(transport_type, options) do
    case transport_type do
      :stdio -> MCPEx.Transport.Stdio.start_link(options)
      :http -> MCPEx.Transport.Http.start_link(options)
      :test -> MCPEx.Transport.Test.start_link(options)
      _ -> {:error, "Unsupported transport type: #{inspect(transport_type)}"}
    end
  end

  @doc """
  Sends a message to the server.

  ## Parameters

  * `transport` - The transport process
  * `message` - The message to send

  ## Returns

  * `:ok` - The message was sent successfully
  * `{:error, reason}` - Failed to send the message
  """
  @spec send(pid(), String.t()) :: :ok | {:error, term()}
  def send(transport, message) do
    case Process.alive?(transport) do
      true ->
        try do
          # Call appropriate function based on transport type
          module = transport_module(transport)
          if function_exported?(module, :send_message, 2) do
            apply(module, :send_message, [transport, message])
          else
            GenServer.call(transport, {:send, message})
          end
        catch
          :exit, _ -> {:error, "Transport process not responding"}
        end
      false ->
        {:error, "Transport process not alive"}
    end
  end
  
  # Get the module for a given transport process
  defp transport_module(transport) do
    case Process.info(transport, :dictionary) do
      {:dictionary, dictionary} ->
        case Keyword.get(dictionary, :"$initial_call") do
          {module, _, _} -> module
          _ -> MCPEx.Transport.Stdio  # Default to Stdio as fallback
        end
      _ ->
        MCPEx.Transport.Stdio  # Default to Stdio as fallback
    end
  end

  @doc """
  Closes the transport connection.

  ## Parameters

  * `transport` - The transport to close

  ## Returns

  * `:ok` - The connection was closed successfully
  * `{:error, reason}` - Failed to close the connection
  """
  @spec close(pid()) :: :ok | {:error, term()}
  def close(transport) do
    case Process.alive?(transport) do
      true ->
        try do
          GenServer.call(transport, :close)
        catch
          :exit, _ -> {:error, "Transport process not responding"}
        end
      false ->
        # Already dead, so consider it closed
        :ok
    end
  end
end