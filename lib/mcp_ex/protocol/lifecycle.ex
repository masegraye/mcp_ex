defmodule MCPEx.Protocol.Lifecycle do
  @moduledoc """
  Manages the MCP protocol lifecycle.
  
  This module handles the initialization, operation, and shutdown
  phases of the protocol interaction, focusing on:
  
  1. Client and server initialization with capability negotiation
  2. Protocol version compatibility checking
  3. Required capability verification
  4. Handling the protocol state transitions
  """
  
  alias MCPEx.Protocol.Capabilities
  alias MCPEx.Protocol.Types.{InitializeRequest, InitializeResult, InitializedNotification}
  
  @default_version "2025-03-26"
  @supported_versions ["2025-03-26", "2024-11-05"]
  
  @doc """
  Creates an initialization request according to the MCP specification.
  
  ## Parameters
  
  * `client_info` - Information about the client (name, version)
  * `capabilities` - The client's capabilities
  * `protocol_version` - The protocol version to use (defaults to latest)
  
  ## Returns
  
  * `InitializeRequest.t()` - The initialization request struct
  
  ## Examples
  
      iex> Lifecycle.create_initialize_request(
      ...>   %{name: "TestClient", version: "1.0.0"},
      ...>   %{sampling: %{}}
      ...> )
  """
  @spec create_initialize_request(map(), map(), String.t()) :: InitializeRequest.t()
  def create_initialize_request(client_info, capabilities, protocol_version \\ @default_version) do
    %InitializeRequest{
      id: System.unique_integer([:positive]),
      client_info: client_info,
      protocol_version: protocol_version,
      capabilities: capabilities
    }
  end
  
  @doc """
  Creates an initialized notification according to the MCP specification.
  
  ## Returns
  
  * `InitializedNotification.t()` - The initialized notification struct
  
  ## Examples
  
      iex> Lifecycle.create_initialized_notification()
      %InitializedNotification{}
  """
  @spec create_initialized_notification() :: InitializedNotification.t()
  def create_initialized_notification do
    %InitializedNotification{}
  end
  
  @doc """
  Processes an initialization response from the server.
  
  ## Parameters
  
  * `response` - The server's response to the initialization request
  
  ## Returns
  
  * `{:ok, InitializeResult.t()}` - Successful initialization
  * `{:error, reason}` - Error during initialization
  
  ## Examples
  
      iex> response = %{
      ...>   jsonrpc: "2.0", id: 1, 
      ...>   result: %{
      ...>     serverInfo: %{name: "Server", version: "1.0"},
      ...>     protocolVersion: "2025-03-26",
      ...>     capabilities: %{}
      ...>   }
      ...> }
      iex> {:ok, result} = Lifecycle.process_initialize_response(response)
  """
  @spec process_initialize_response(map()) :: {:ok, InitializeResult.t()} | {:error, String.t()}
  def process_initialize_response(response) do
    case response do
      %{error: error} ->
        {:error, "Server returned error: #{error.message}"}
        
      %{result: result} when is_map(result) ->
        if Map.has_key?(result, :serverInfo) and 
           Map.has_key?(result, :protocolVersion) and
           Map.has_key?(result, :capabilities) do
          
          # Convert to InitializeResult struct
          {:ok, %InitializeResult{
            id: response.id,
            server_info: result.serverInfo,
            protocol_version: result.protocolVersion,
            capabilities: result.capabilities
          }}
        else
          {:error, "Missing required fields in initialize response"}
        end
        
      _ ->
        {:error, "Invalid initialize response format"}
    end
  end
  
  @doc """
  Processes server capabilities from the initialize response.
  
  ## Parameters
  
  * `capabilities` - The raw server capabilities map
  
  ## Returns
  
  * `{:ok, map()}` - Processed capabilities
  * `{:error, reason}` - Error processing capabilities
  """
  @spec process_server_capabilities(map() | nil) :: {:ok, map()} | {:error, String.t()}
  def process_server_capabilities(capabilities) when is_map(capabilities) do
    {:ok, capabilities}
  end
  
  def process_server_capabilities(nil) do
    {:error, "Server capabilities are missing"}
  end
  
  def process_server_capabilities(_) do
    {:error, "Invalid server capabilities format"}
  end
  
  @doc """
  Validates a server initialization response.
  
  ## Parameters
  
  * `response` - The server's response to the initialization request
  
  ## Returns
  
  * `:ok` - The initialization is valid
  * `{:error, reason}` - There are issues with the initialization
  """
  @spec validate_server_initialization(map()) :: :ok | {:error, String.t()}
  def validate_server_initialization(response) do
    with {:ok, initialize_result} <- process_initialize_response(response),
         :ok <- validate_protocol_version(initialize_result.protocol_version),
         {:ok, _} <- process_server_capabilities(initialize_result.capabilities) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Validates that a protocol version is supported by the client.
  
  ## Parameters
  
  * `version` - The protocol version to check
  
  ## Returns
  
  * `:ok` - The version is supported
  * `{:error, reason}` - The version is not supported
  """
  @spec validate_protocol_version(String.t()) :: :ok | {:error, String.t()}
  def validate_protocol_version(version) do
    if version in @supported_versions do
      :ok
    else
      {:error, "Unsupported protocol version: #{version}. Supported versions: #{inspect(@supported_versions)}"}
    end
  end
  
  @doc """
  Checks that required capabilities are available in the server capabilities.
  
  ## Parameters
  
  * `server_capabilities` - The server's capabilities
  * `required_capabilities` - List of required capabilities
  
  ## Returns
  
  * `:ok` - All required capabilities are available
  * `{:error, reason}` - Some required capabilities are missing
  
  ## Examples
  
  Simple capability list:
  
      iex> server_capabilities = %{resources: %{}, tools: %{}}
      iex> Lifecycle.check_required_capabilities(server_capabilities, [:resources])
      :ok
      
  With sub-capability requirements:
  
      iex> server_capabilities = %{resources: %{subscribe: true}}
      iex> Lifecycle.check_required_capabilities(server_capabilities, [resources: [:subscribe]])
      :ok
  """
  @spec check_required_capabilities(map(), list()) :: :ok | {:error, String.t()}
  def check_required_capabilities(server_capabilities, required_capabilities) do
    # Process the required capabilities list, which can include atoms or keyword entries
    missing = Enum.reduce(required_capabilities, [], fn requirement, acc ->
      case requirement do
        {capability, sub_capabilities} when is_atom(capability) and is_list(sub_capabilities) ->
          # Check for capability and sub-capabilities
          if Capabilities.has_capability?(server_capabilities, capability) do
            # Check each sub-capability
            missing_sub = Enum.filter(sub_capabilities, fn sub ->
              not Capabilities.has_capability?(server_capabilities, capability, sub)
            end)
            
            if Enum.empty?(missing_sub) do
              acc
            else
              # Add to missing list with sub-capabilities
              [{capability, missing_sub} | acc]
            end
          else
            # Capability is missing entirely
            [capability | acc]
          end
          
        capability when is_atom(capability) ->
          # Simple capability check
          if Capabilities.has_capability?(server_capabilities, capability) do
            acc
          else
            [capability | acc]
          end
          
        _ ->
          # Invalid requirement format
          acc
      end
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required capabilities: #{inspect(missing)}"}
    end
  end
end