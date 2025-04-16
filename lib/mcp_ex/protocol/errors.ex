defmodule MCPEx.Protocol.Errors do
  @moduledoc """
  Defines and handles MCP protocol errors.
  
  This module provides utilities for creating and processing
  JSON-RPC error objects according to the MCP specification.
  
  ## JSON-RPC Error Codes
  
  ### Pre-defined JSON-RPC 2.0 error codes:
  
  - `-32700`: Parse error - Invalid JSON was received
  - `-32600`: Invalid Request - The JSON sent is not a valid Request object
  - `-32601`: Method not found - The method does not exist / is not available
  - `-32602`: Invalid params - Invalid method parameter(s)
  - `-32603`: Internal error - Internal JSON-RPC error
  - `-32000 to -32099`: Server error - Reserved for implementation-defined server-errors
  
  ### MCP-specific error codes:
  
  - `-32800`: Request cancelled - The request was cancelled
  - `-32801`: Content too large - The content is too large
  """
  
  alias MCPEx.Protocol.JsonRpc
  
  # JSON-RPC 2.0 standard error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603
  @server_error -32000
  
  # MCP-specific error codes
  @request_cancelled -32800
  @content_too_large -32801
  
  @doc """
  Creates a JSON-RPC error object.
  
  ## Parameters
  
  * `code` - The error code
  * `message` - The error message
  * `data` - Optional additional data
  
  ## Returns
  
  * `map()` - The error object
  
  ## Examples
  
      iex> MCPEx.Protocol.Errors.create_error(-32600, "Invalid Request")
      %{code: -32600, message: "Invalid Request"}
      
      iex> MCPEx.Protocol.Errors.create_error(-32602, "Missing param", %{param: "id"})
      %{code: -32602, message: "Missing param", data: %{param: "id"}}
  """
  @spec create_error(integer(), String.t(), map() | nil) :: map()
  def create_error(code, message, data \\ nil) do
    error = %{
      code: code,
      message: message
    }
    
    if data do
      Map.put(error, :data, data)
    else
      error
    end
  end
  
  @doc """
  Creates a parse error object.
  
  ## Parameters
  
  * `message` - Optional custom error message
  
  ## Returns
  
  * `map()` - The error object
  
  ## Examples
  
      iex> MCPEx.Protocol.Errors.parse_error()
      %{code: -32700, message: "Parse error"}
  """
  @spec parse_error(String.t()) :: map()
  def parse_error(message \\ "Parse error") do
    create_error(@parse_error, message)
  end
  
  @doc """
  Creates an invalid request error object.
  
  ## Parameters
  
  * `message` - Optional custom error message
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec invalid_request(String.t()) :: map()
  def invalid_request(message \\ "Invalid Request") do
    create_error(@invalid_request, message)
  end
  
  @doc """
  Creates a method not found error object.
  
  ## Parameters
  
  * `method` - The method that was not found
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec method_not_found(String.t()) :: map()
  def method_not_found(method) do
    create_error(@method_not_found, "Method not found: #{method}")
  end
  
  @doc """
  Creates an invalid params error object.
  
  ## Parameters
  
  * `details` - Details about the invalid parameters
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec invalid_params(String.t()) :: map()
  def invalid_params(details) do
    create_error(@invalid_params, "Invalid params: #{details}")
  end
  
  @doc """
  Creates an internal error object.
  
  ## Parameters
  
  * `details` - Optional details about the internal error
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec internal_error(String.t()) :: map()
  def internal_error(details \\ "Server error") do
    create_error(@internal_error, "Internal error: #{details}")
  end
  
  @doc """
  Creates a request cancelled error object.
  
  ## Parameters
  
  * `details` - Details about the cancellation
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec request_cancelled(String.t()) :: map()
  def request_cancelled(details) do
    create_error(@request_cancelled, "Request cancelled: #{details}")
  end
  
  @doc """
  Creates a content too large error object.
  
  ## Parameters
  
  * `details` - Details about the content size issues
  
  ## Returns
  
  * `map()` - The error object
  """
  @spec content_too_large(String.t()) :: map()
  def content_too_large(details) do
    create_error(@content_too_large, "Content too large: #{details}")
  end
  
  @doc """
  Creates a complete JSON-RPC error response.
  
  ## Parameters
  
  * `id` - The request ID (or nil for notifications)
  * `error` - The error object
  
  ## Returns
  
  * `map()` - The complete error response
  """
  @spec encode_error_response(integer() | String.t() | nil, map()) :: map()
  def encode_error_response(id, error) do
    %{
      jsonrpc: "2.0",
      id: id,
      error: error
    }
  end
  
  @doc """
  Returns a JSON string for an error response.
  
  ## Parameters
  
  * `id` - The request ID
  * `error` - The error object
  
  ## Returns
  
  * `String.t()` - The JSON string
  """
  @spec error_response_json(integer() | String.t() | nil, map()) :: String.t()
  def error_response_json(id, error) do
    # We don't need to use the response, just encode the error directly
    JsonRpc.encode_error(id, error)
  end
  
  @doc """
  Handles various error types and converts them to standardized JSON-RPC errors.
  
  ## Parameters
  
  * `error` - The error to handle
  
  ## Returns
  
  * `{:error, map()}` - Standardized error map
  """
  @spec handle_error(term()) :: {:error, map()}
  def handle_error(error) do
    case error do
      %Jason.DecodeError{} ->
        {:error, parse_error("Parse error: Invalid JSON")}
        
      {:error, :timeout} ->
        {:error, create_error(@server_error, "Request timed out")}
        
      {:error, reason} when is_atom(reason) ->
        {:error, internal_error("#{reason}")}
        
      {:error, %{code: _code, message: _message} = err} ->
        {:error, err}
        
      {:error, reason} ->
        {:error, internal_error("#{inspect(reason)}")}
        
      _ ->
        {:error, internal_error("#{inspect(error)}")}
    end
  end
end