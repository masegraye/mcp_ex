defmodule MCPEx.Protocol.Types do
  @moduledoc """
  Type definitions for MCP protocol messages.
  
  This module provides Elixir structs representing the various
  message types in the MCP protocol, along with conversion functions
  between structs and JSON-RPC maps.
  """
  
  @type message :: map()
  
  # ===== Message Type Structs =====
  
  defmodule InitializeRequest do
    @moduledoc "Represents an initialize request"
    
    @type t :: %__MODULE__{
      id: integer() | String.t(),
      client_info: map(),
      protocol_version: String.t(),
      capabilities: map()
    }
    
    defstruct [:id, :client_info, :protocol_version, :capabilities]
  end
  
  defmodule InitializeResult do
    @moduledoc "Represents an initialize response"
    
    @type t :: %__MODULE__{
      id: integer() | String.t(),
      server_info: map(),
      protocol_version: String.t(),
      capabilities: map()
    }
    
    defstruct [:id, :server_info, :protocol_version, :capabilities]
  end
  
  defmodule InitializedNotification do
    @moduledoc "Represents an initialized notification"
    
    @type t :: %__MODULE__{}
    
    defstruct []
  end
  
  defmodule ReadResourceRequest do
    @moduledoc "Represents a resources/read request"
    
    @type t :: %__MODULE__{
      id: integer() | String.t(),
      uri: String.t(),
      range: map() | nil
    }
    
    defstruct [:id, :uri, :range]
  end
  
  defmodule ResourceContent do
    @moduledoc """
    Represents content types that can be sent in resources or
    other messages. This includes text, images, audio, or embedded 
    resources.
    """
    
    @type t :: map()
    
    @doc "Creates a text content object"
    @spec text(String.t()) :: map()
    def text(content) do
      %{
        type: "text",
        text: content
      }
    end
    
    @doc "Creates an image content object"
    @spec image(String.t(), String.t()) :: map()
    def image(data, mime_type) do
      %{
        type: "image",
        data: data,
        mime_type: mime_type
      }
    end
    
    @doc "Creates an audio content object"
    @spec audio(String.t(), String.t()) :: map()
    def audio(data, mime_type) do
      %{
        type: "audio",
        data: data,
        mime_type: mime_type
      }
    end
    
    @doc "Creates a resource reference"
    @spec resource(String.t()) :: map()
    def resource(uri) do
      %{
        type: "resource",
        resource: uri
      }
    end
  end
  
  # ===== Conversion Functions =====
  
  @doc """
  Converts a protocol struct to a JSON-RPC map representation.
  
  ## Parameters
  
  * `struct` - The protocol struct to convert
  
  ## Returns
  
  * `map()` - The JSON-RPC map
  
  ## Examples
  
      iex> request = %InitializeRequest{id: 1, client_info: %{name: "client"}}
      iex> MCPEx.Protocol.Types.to_map(request)
      %{jsonrpc: "2.0", id: 1, method: "initialize", params: %{clientInfo: %{name: "client"}}}
  """
  @spec to_map(struct()) :: map()
  def to_map(%InitializeRequest{} = request) do
    %{
      jsonrpc: "2.0",
      id: request.id,
      method: "initialize",
      params: %{
        clientInfo: request.client_info,
        protocolVersion: request.protocol_version,
        capabilities: request.capabilities
      }
    }
  end
  
  def to_map(%InitializeResult{} = result) do
    %{
      jsonrpc: "2.0",
      id: result.id,
      result: %{
        serverInfo: result.server_info,
        protocolVersion: result.protocol_version,
        capabilities: result.capabilities
      }
    }
  end
  
  def to_map(%InitializedNotification{}) do
    %{
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: %{}
    }
  end
  
  def to_map(%ReadResourceRequest{} = request) do
    params = %{uri: request.uri}
    
    params = 
      if request.range do
        Map.put(params, :range, request.range)
      else
        params
      end
    
    %{
      jsonrpc: "2.0",
      id: request.id,
      method: "resources/read",
      params: params
    }
  end
  
  @doc """
  Converts a JSON-RPC map to the appropriate protocol struct.
  
  ## Parameters
  
  * `map` - The JSON-RPC map to convert
  
  ## Returns
  
  * `{:ok, struct()}` - The converted protocol struct
  * `{:error, String.t()}` - Error message if the map doesn't match a known type
  
  ## Examples
  
      iex> map = %{jsonrpc: "2.0", id: 1, method: "initialize", params: %{}}
      iex> {:ok, request} = MCPEx.Protocol.Types.from_map(map)
      iex> request.__struct__
      MCPEx.Protocol.Types.InitializeRequest
  """
  @spec from_map(map()) :: {:ok, struct()} | {:error, String.t()}
  def from_map(map) do
    case detect_message_type(map) do
      {:ok, InitializeRequest} ->
        {:ok, %InitializeRequest{
          id: map.id,
          client_info: map.params.clientInfo,
          protocol_version: map.params.protocolVersion,
          capabilities: map.params.capabilities
        }}
      
      {:ok, InitializeResult} ->
        {:ok, %InitializeResult{
          id: map.id,
          server_info: map.result.serverInfo,
          protocol_version: map.result.protocolVersion,
          capabilities: map.result.capabilities
        }}
      
      {:ok, InitializedNotification} ->
        {:ok, %InitializedNotification{}}
      
      {:ok, ReadResourceRequest} ->
        {:ok, %ReadResourceRequest{
          id: map.id,
          uri: map.params.uri,
          range: Map.get(map.params, :range)
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Detects the message type based on JSON-RPC message structure.
  
  ## Parameters
  
  * `map` - The JSON-RPC message to analyze
  
  ## Returns
  
  * `{:ok, module()}` - The detected struct type
  * `{:error, String.t()}` - Error message if the type is unknown
  """
  @spec detect_message_type(map()) :: {:ok, module()} | {:error, String.t()}
  def detect_message_type(map) do
    cond do
      # Request types
      Map.has_key?(map, :method) and Map.has_key?(map, :id) ->
        case map.method do
          "initialize" -> 
            {:ok, InitializeRequest}
            
          "resources/read" -> 
            {:ok, ReadResourceRequest}
            
          _ -> 
            {:error, "Unknown request method: #{map.method}"}
        end
        
      # Response types
      Map.has_key?(map, :result) and Map.has_key?(map, :id) ->
        result = map.result
        
        cond do
          is_map(result) and Map.has_key?(result, :serverInfo) and 
          Map.has_key?(result, :protocolVersion) -> 
            {:ok, InitializeResult}
            
          true -> 
            {:error, "Unknown result type"}
        end
        
      # Notification types (no ID)
      Map.has_key?(map, :method) and not Map.has_key?(map, :id) ->
        case map.method do
          "notifications/initialized" -> 
            {:ok, InitializedNotification}
            
          _ -> 
            {:error, "Unknown notification method: #{map.method}"}
        end
        
      true ->
        {:error, "Unknown message type"}
    end
  end
end