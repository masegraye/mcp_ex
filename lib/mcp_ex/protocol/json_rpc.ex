defmodule MCPEx.Protocol.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 protocol implementation for MCP client.

  This module handles encoding and decoding of JSON-RPC 2.0 messages according to the
  Model Context Protocol specification. It supports both individual messages and batches
  of messages as defined in the JSON-RPC 2.0 specification.
  """

  @doc """
  Encodes a JSON-RPC request.

  ## Parameters

  * `id` - The request ID
  * `method` - The method name to call
  * `params` - The parameters to pass to the method

  ## Returns

  * `String.t()` - The encoded JSON-RPC request
  """
  @spec encode_request(integer() | String.t(), String.t(), map()) :: String.t()
  def encode_request(id, method, params) do
    request = %{
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: params
    }

    Jason.encode!(request)
  end

  @doc """
  Encodes a JSON-RPC notification.

  ## Parameters

  * `method` - The method name to call
  * `params` - The parameters to pass to the method

  ## Returns

  * `String.t()` - The encoded JSON-RPC notification
  """
  @spec encode_notification(String.t(), map()) :: String.t()
  def encode_notification(method, params) do
    notification = %{
      jsonrpc: "2.0",
      method: method,
      params: params
    }

    Jason.encode!(notification)
  end

  @doc """
  Encodes a JSON-RPC response.

  ## Parameters

  * `id` - The request ID
  * `result` - The result of the request

  ## Returns

  * `String.t()` - The encoded JSON-RPC response
  """
  @spec encode_response(integer() | String.t(), map()) :: String.t()
  def encode_response(id, result) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: result
    }

    Jason.encode!(response)
  end

  @doc """
  Encodes a JSON-RPC error response.

  ## Parameters

  * `id` - The request ID
  * `error` - The error details

  ## Returns

  * `String.t()` - The encoded JSON-RPC error response
  """
  @spec encode_error(integer() | String.t(), map()) :: String.t()
  def encode_error(id, error) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      error: error
    }

    Jason.encode!(response)
  end
  
  @doc """
  Encodes a JSON-RPC error response with code and message.

  ## Parameters

  * `id` - The request ID
  * `code` - The error code
  * `message` - The error message

  ## Returns

  * `String.t()` - The encoded JSON-RPC error response
  """
  @spec encode_error_response(integer() | String.t(), integer(), String.t()) :: String.t()
  def encode_error_response(id, code, message) do
    error = %{
      code: code,
      message: message
    }
    
    encode_error(id, error)
  end

  @doc """
  Decodes a JSON-RPC message.

  ## Parameters

  * `json` - The JSON-RPC message to decode

  ## Returns

  * `{:ok, map()}` - The decoded message
  * `{:error, reason}` - Error decoding the message
  """
  @spec decode_message(String.t()) :: {:ok, map()} | {:error, term()}
  def decode_message(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, message} -> validate_message(message)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a decoded JSON-RPC message.

  ## Parameters

  * `message` - The decoded message to validate

  ## Returns

  * `{:ok, map()}` - The validated message
  * `{:error, reason}` - Invalid message
  """
  @spec validate_message(map()) :: {:ok, map()} | {:error, term()}
  def validate_message(message) do
    cond do
      # Request
      Map.has_key?(message, :id) and Map.has_key?(message, :method) ->
        validate_request(message)

      # Response
      Map.has_key?(message, :id) and Map.has_key?(message, :result) ->
        validate_response(message)

      # Error
      Map.has_key?(message, :id) and Map.has_key?(message, :error) ->
        validate_error(message)

      # Notification
      not Map.has_key?(message, :id) and Map.has_key?(message, :method) ->
        validate_notification(message)

      true ->
        {:error, "Invalid JSON-RPC message"}
    end
  end

  # Private helpers for validation

  defp validate_request(request) do
    if request.jsonrpc == "2.0" and is_binary(request.method) do
      {:ok, request}
    else
      {:error, "Invalid JSON-RPC request"}
    end
  end

  defp validate_response(response) do
    if response.jsonrpc == "2.0" do
      {:ok, response}
    else
      {:error, "Invalid JSON-RPC response"}
    end
  end

  defp validate_error(error) do
    if error.jsonrpc == "2.0" and is_map(error.error) and
         Map.has_key?(error.error, :code) and Map.has_key?(error.error, :message) do
      {:ok, error}
    else
      {:error, "Invalid JSON-RPC error"}
    end
  end

  defp validate_notification(notification) do
    if notification.jsonrpc == "2.0" and is_binary(notification.method) do
      {:ok, notification}
    else
      {:error, "Invalid JSON-RPC notification"}
    end
  end
  
  @doc """
  Encodes a batch of JSON-RPC messages.
  
  ## Parameters
  
  * `messages` - A list of JSON-RPC messages (requests, notifications, responses)
  
  ## Returns
  
  * `String.t()` - The encoded JSON-RPC batch
  """
  @spec encode_batch([map()]) :: String.t()
  def encode_batch(messages) when is_list(messages) do
    Jason.encode!(messages)
  end
  
  @doc """
  Decodes a JSON-RPC batch message.
  
  ## Parameters
  
  * `json` - The JSON-RPC batch to decode
  
  ## Returns
  
  * `{:ok, [map()]}` - The decoded messages
  * `{:error, reason}` - Error decoding the messages
  """
  @spec decode_batch(String.t()) :: {:ok, [map()]} | {:error, term()}
  def decode_batch(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, messages} when is_list(messages) -> 
        # Process each message in the batch
        results = Enum.map(messages, &validate_message/1)
        if Enum.any?(results, fn {status, _} -> status == :error end) do
          # If any message failed validation, return an error
          {:error, "Invalid batch: contains invalid messages"}
        else
          # Extract just the messages from the {:ok, message} tuples
          {:ok, Enum.map(results, fn {:ok, msg} -> msg end)}
        end
      {:ok, _} -> {:error, "Invalid JSON-RPC batch: not an array"}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Generates a unique request ID.
  
  ## Returns
  
  * `integer()` - A unique request ID
  """
  @spec generate_id() :: integer()
  def generate_id do
    System.unique_integer([:positive])
  end
  
  @doc """
  Creates an initialize request message as defined in the MCP specification.
  
  ## Parameters
  
  * `client_info` - Information about the client
  * `protocol_version` - Protocol version to use
  * `capabilities` - Client capabilities
  
  ## Returns
  
  * `map()` - The initialize request message
  """
  @spec create_initialize_request(map(), String.t(), map()) :: map()
  def create_initialize_request(client_info, protocol_version, capabilities) do
    %{
      jsonrpc: "2.0",
      id: generate_id(),
      method: "initialize",
      params: %{
        clientInfo: client_info,
        protocolVersion: protocol_version,
        capabilities: capabilities
      }
    }
  end
end