defmodule MCPEx.Protocol.Capabilities do
  @moduledoc """
  Handles protocol capabilities and version negotiation.
  
  This module provides utilities for:
  - Creating client and server capability maps
  - Checking for capability support
  - Negotiating protocol versions
  - Validating capability requirements
  
  The MCP protocol uses capabilities to allow clients and servers to 
  declare which features they support, with both required and optional
  capabilities.
  """
  
  @latest_version "2025-03-26"
  @supported_versions ["2025-03-26", "2024-11-05"]
  
  @doc """
  Returns the current protocol version supported by this client.
  """
  @spec protocol_version() :: String.t()
  def protocol_version, do: @latest_version
  
  @doc """
  Gets the latest supported protocol version.
  
  ## Returns
  
  * `String.t()` - The latest supported version
  """
  @spec latest_version() :: String.t()
  def latest_version, do: @latest_version
  
  @doc """
  Gets all supported protocol versions.
  
  ## Returns
  
  * `[String.t()]` - List of supported versions
  """
  @spec supported_versions() :: [String.t()]
  def supported_versions, do: @supported_versions
  
  @doc """
  Creates a client capabilities object according to the MCP specification.
  
  ## Options
  
  * `sampling` - Whether to include sampling capability (default: true)
  * `roots` - Whether to include roots capability (default: false)
  * `roots_list_changed` - Whether roots supports list change notifications (default: false)
  * `experimental` - Optional map of experimental capabilities
  
  ## Returns
  
  * `map()` - The client capabilities object ready for initialization
  
  ## Examples
  
      iex> MCPEx.Protocol.Capabilities.create_client_capabilities()
      %{sampling: %{}}
      
      iex> MCPEx.Protocol.Capabilities.create_client_capabilities(roots: true, roots_list_changed: true)
      %{sampling: %{}, roots: %{listChanged: true}}
  """
  @spec create_client_capabilities(keyword()) :: map()
  def create_client_capabilities(options \\ []) do
    capabilities = %{}
    
    capabilities =
      if Keyword.get(options, :sampling, true) do
        Map.put(capabilities, :sampling, %{})
      else
        capabilities
      end
    
    capabilities =
      if Keyword.get(options, :roots, false) do
        roots_capabilities = %{}
        
        roots_capabilities =
          if Keyword.get(options, :roots_list_changed, false) do
            Map.put(roots_capabilities, :listChanged, true)
          else
            roots_capabilities
          end
        
        Map.put(capabilities, :roots, roots_capabilities)
      else
        capabilities
      end
    
    capabilities =
      if experimental = Keyword.get(options, :experimental) do
        Map.put(capabilities, :experimental, experimental)
      else
        capabilities
      end
    
    capabilities
  end
  
  @doc """
  Builds client capabilities map based on provided capabilities list. 
  DEPRECATED: Use create_client_capabilities/1 instead.
  """
  @spec build_client_capabilities(list(atom())) :: map()
  def build_client_capabilities(capabilities) do
    base_capabilities = %{}

    Enum.reduce(capabilities, base_capabilities, fn capability, acc ->
      case capability do
        :sampling -> Map.put(acc, :sampling, %{})
        :roots -> Map.put(acc, :roots, %{listChanged: true})
        _ -> acc
      end
    end)
  end
  
  @doc """
  Creates a server capabilities object according to the MCP specification.
  
  ## Options
  
  * `resources` - Whether to include resources capability (default: false)
  * `resources_subscribe` - Whether resources can be subscribed to (default: false)
  * `resources_list_changed` - Whether resources supports list change notifications (default: false)
  * `tools` - Whether to include tools capability (default: false)
  * `tools_list_changed` - Whether tools supports list change notifications (default: false)
  * `prompts` - Whether to include prompts capability (default: false)
  * `prompts_list_changed` - Whether prompts supports list change notifications (default: false)
  * `logging` - Whether to include logging capability (default: false)
  * `experimental` - Optional map of experimental capabilities
  
  ## Returns
  
  * `map()` - The server capabilities object
  
  ## Examples
  
      iex> MCPEx.Protocol.Capabilities.create_server_capabilities(resources: true, resources_subscribe: true)
      %{resources: %{subscribe: true}}
  """
  @spec create_server_capabilities(keyword()) :: map()
  def create_server_capabilities(options \\ []) do
    capabilities = %{}
    
    capabilities = 
      if Keyword.get(options, :resources, false) do
        resources_capabilities = %{}
        
        resources_capabilities =
          if Keyword.get(options, :resources_subscribe, false) do
            Map.put(resources_capabilities, :subscribe, true)
          else
            resources_capabilities
          end
        
        resources_capabilities =
          if Keyword.get(options, :resources_list_changed, false) do
            Map.put(resources_capabilities, :listChanged, true)
          else
            resources_capabilities
          end
        
        Map.put(capabilities, :resources, resources_capabilities)
      else
        capabilities
      end
    
    capabilities =
      if Keyword.get(options, :tools, false) do
        tools_capabilities = %{}
        
        tools_capabilities =
          if Keyword.get(options, :tools_list_changed, false) do
            Map.put(tools_capabilities, :listChanged, true)
          else
            tools_capabilities
          end
        
        Map.put(capabilities, :tools, tools_capabilities)
      else
        capabilities
      end
    
    capabilities =
      if Keyword.get(options, :prompts, false) do
        prompts_capabilities = %{}
        
        prompts_capabilities =
          if Keyword.get(options, :prompts_list_changed, false) do
            Map.put(prompts_capabilities, :listChanged, true)
          else
            prompts_capabilities
          end
        
        Map.put(capabilities, :prompts, prompts_capabilities)
      else
        capabilities
      end
    
    capabilities =
      if Keyword.get(options, :logging, false) do
        Map.put(capabilities, :logging, %{})
      else
        capabilities
      end
    
    capabilities =
      if experimental = Keyword.get(options, :experimental) do
        Map.put(capabilities, :experimental, experimental)
      else
        capabilities
      end
    
    capabilities
  end
  
  @doc """
  Parses server capabilities from an initialize response.
  
  ## Parameters
  
  * `response` - The initialization response from the server
  
  ## Returns
  
  * `{:ok, capabilities}` - The parsed server capabilities
  * `{:error, reason}` - Error parsing capabilities
  """
  @spec parse_server_capabilities(map()) :: {:ok, map()} | {:error, String.t()}
  def parse_server_capabilities(server_capabilities) do
    if is_map(server_capabilities) do
      parsed = %{
        resources: parse_capability(server_capabilities, :resources),
        tools: parse_capability(server_capabilities, :tools),
        prompts: parse_capability(server_capabilities, :prompts),
        logging: parse_capability(server_capabilities, :logging),
        completions: parse_capability(server_capabilities, :completions),
        experimental: Map.get(server_capabilities, :experimental, %{})
      }
      {:ok, parsed}
    else
      {:error, "Invalid server capabilities format"}
    end
  end
  
  @doc """
  Checks if a specific capability is available.
  
  ## Parameters
  
  * `capabilities` - The capability map to check
  * `capability` - The main capability to check for
  * `sub_capability` - Optional sub-capability to check for
  
  ## Returns
  
  * `boolean()` - `true` if the capability is available, otherwise `false`
  
  ## Examples
  
      iex> capabilities = %{resources: %{subscribe: true}}
      iex> MCPEx.Protocol.Capabilities.has_capability?(capabilities, :resources)
      true
      
      iex> capabilities = %{resources: %{subscribe: true}}
      iex> MCPEx.Protocol.Capabilities.has_capability?(capabilities, :resources, :subscribe)
      true
      
      iex> capabilities = %{resources: %{subscribe: true}}
      iex> MCPEx.Protocol.Capabilities.has_capability?(capabilities, :sampling)
      false
  """
  @spec has_capability?(map(), atom(), atom() | nil) :: boolean()
  def has_capability?(capabilities, capability, sub_capability \\ nil)
  
  def has_capability?(capabilities, capability, nil) do
    Map.has_key?(capabilities, capability)
  end
  
  def has_capability?(capabilities, capability, sub_capability) do
    case Map.get(capabilities, capability) do
      nil -> false
      cap_info when is_map(cap_info) -> Map.get(cap_info, sub_capability, false)
      _ -> false
    end
  end
  
  @doc """
  Negotiates a common protocol version between client and server.
  
  ## Parameters
  
  * `client_versions` - Client supported version(s)
  * `server_versions` - Server supported version(s)
  
  ## Returns
  
  * `{:ok, version}` - The negotiated common version
  * `{:error, reason}` - Error when no common version exists
  
  ## Examples
  
      iex> client_version = "2025-03-26"
      iex> server_versions = ["2025-03-26", "2024-11-05"]
      iex> MCPEx.Protocol.Capabilities.negotiate_version(client_version, server_versions)
      {:ok, "2025-03-26"}
  """
  @spec negotiate_version(String.t() | [String.t()], [String.t()]) :: 
    {:ok, String.t()} | {:error, String.t()}
  def negotiate_version(client_versions, server_versions) do
    client_versions_list = List.wrap(client_versions)
    
    # Find common versions
    common_versions = 
      for client_v <- client_versions_list,
          server_v <- server_versions,
          client_v == server_v,
          do: client_v
    
    case common_versions do
      [] ->
        {:error, "No common protocol version between client #{inspect(client_versions_list)} and server #{inspect(server_versions)}"}
      versions ->
        # Use the lexicographically highest version (which should be the latest)
        {:ok, Enum.max(versions)}
    end
  end
  
  @doc """
  Validates that required capabilities are supported.
  
  ## Parameters
  
  * `required_capabilities` - List of capability atoms that are required
  * `available_capabilities` - Map of capabilities that are available
  
  ## Returns
  
  * `:ok` - All required capabilities are available
  * `{:error, reason}` - Some required capabilities are missing
  
  ## Examples
  
      iex> MCPEx.Protocol.Capabilities.validate_capability_support(
      ...>   [:sampling], 
      ...>   %{resources: %{}, sampling: %{}}
      ...> )
      :ok
  """
  @spec validate_capability_support([atom()], map()) :: :ok | {:error, String.t()}
  def validate_capability_support(required_capabilities, available_capabilities) do
    missing_capabilities = Enum.filter(required_capabilities, fn capability ->
      not has_capability?(available_capabilities, capability)
    end)
    
    if Enum.empty?(missing_capabilities) do
      :ok
    else
      {
        :error, 
        "Required capabilities not supported: #{inspect(missing_capabilities)}"
      }
    end
  end

  # Private helper functions
  
  defp parse_capability(capabilities, name) do
    capability = Map.get(capabilities, name)
    if is_map(capability), do: capability, else: nil
  end
end