defmodule MCPEx.Protocol.Schemas do
  @moduledoc """
  JSON Schema validation for MCP protocol messages.

  This module provides validation of incoming and outgoing messages
  against the MCP protocol specification schemas.
  """
  
  require Logger
  
  # Message type mapping based on structure
  @message_types %{
    # Request types
    "initialize" => "InitializeRequest",
    "resources/list" => "ListResourcesRequest",
    "resources/read" => "ReadResourceRequest",
    "resources/templates/list" => "ListResourceTemplatesRequest",
    "resources/subscribe" => "SubscribeToResourceRequest",
    "resources/unsubscribe" => "UnsubscribeFromResourceRequest",
    "tools/list" => "ListToolsRequest",
    "tools/call" => "CallToolRequest",
    "prompts/list" => "ListPromptsRequest",
    "prompts/get" => "GetPromptRequest",
    "roots/list" => "ListRootsRequest",
    "sampling/createMessage" => "CreateMessageRequest",
    
    # Notification types
    "notifications/initialized" => "InitializedNotification",
    "notifications/cancelled" => "CancelledNotification",
    "notifications/resources/updated" => "ResourceUpdatedNotification",
    "notifications/resources/list_changed" => "ResourceListChangedNotification",
    "notifications/tools/list_changed" => "ToolListChangedNotification",
    "notifications/prompts/list_changed" => "PromptListChangedNotification",
    "notifications/roots/list_changed" => "RootListChangedNotification",
    "notifications/progress" => "ProgressNotification",
    "$/ping" => "PingNotification"
  }
  
  # Schema path constant - try multiple locations to support both dev and test environments
  @schema_paths [
    # Default production location in the built app
    Path.join([Application.app_dir(:mcp_ex, "priv"), "schema", "2025-03-26", "schema.json"]),
    
    # Development location for tests
    Path.join([File.cwd!(), "priv", "schema", "2025-03-26", "schema.json"]),
    
    # Direct path if running from the package directory
    Path.join([File.cwd!(), "vendor", "mcp_ex", "priv", "schema", "2025-03-26", "schema.json"])
  ]
  
  # Cache schema definitions
  @resolved_schema_cache_key :mcp_ex_schema_cache

  @doc """
  Gets the resolved JSON schema for MCP protocol validation.

  ## Returns

  * `{:ok, map()}` - The resolved schema
  * `{:error, reason}` - Failed to get the schema
  """
  @spec get_resolved_schema() :: {:ok, map()} | {:error, term()}
  def get_resolved_schema do
    # Check if schema is already in process dictionary cache
    case Process.get(@resolved_schema_cache_key) do
      nil ->
        # No cached schema, resolve it
        case resolve_schema() do
          {:ok, schema} ->
            # Cache the schema for future use
            Process.put(@resolved_schema_cache_key, schema)
            {:ok, schema}
          error -> error
        end
      schema ->
        # Return cached schema
        {:ok, schema}
    end
  end
  
  # Load and resolve schema
  defp resolve_schema do
    # Log available paths for debugging
    Enum.each(@schema_paths, fn path ->
      if File.exists?(path) do
        Logger.debug("Schema file found at: #{path}")
      else
        Logger.debug("Schema file NOT found at: #{path}")
      end
    end)
    
    # Try each path in order
    case Enum.reduce_while(@schema_paths, {:error, "Schema file not found"}, fn path, _acc ->
      case File.read(path) do
        {:ok, content} -> 
          Logger.debug("Successfully read schema file from: #{path}")
          case Jason.decode(content) do
            {:ok, schema} -> 
              Logger.debug("Successfully parsed schema JSON")
              {:halt, {:ok, schema}}
            {:error, error} -> 
              Logger.error("Error parsing schema JSON: #{inspect(error)}")
              {:cont, {:error, "Failed to parse schema JSON: #{inspect(error)}"}}
          end
        {:error, reason} -> 
          # Try the next path
          Logger.debug("Could not read from #{path}: #{inspect(reason)}")
          {:cont, {:error, "Schema file not found"}}
      end
    end) do
      {:ok, schema} ->
        # Fully resolve the schema
        try do
          Logger.debug("Resolving schema with ExJsonSchema")
          resolved = ExJsonSchema.Schema.resolve(schema)
          Logger.debug("Schema resolved successfully")
          {:ok, resolved}
        rescue
          e -> 
            Logger.error("Error resolving schema: #{inspect(e)}")
            {:error, "Error resolving schema: #{inspect(e)}"}
        end
      
      error -> error
    end
  end

  @doc """
  Validates a message against a specific schema definition.

  ## Parameters

  * `message` - The message to validate
  * `schema_type` - The name of the schema type (e.g., "InitializeRequest")

  ## Returns

  * `:ok` - The message is valid
  * `{:error, reason}` - The message is invalid
  """
  @spec validate(map(), String.t()) :: :ok | {:error, term()}
  def validate(message, schema_type) do
    case get_resolved_schema() do
      {:ok, resolved_schema} ->
        try do
          # Convert message to string keys for validation
          string_message = message_to_string_keys(message)

          # Check using ex_json_schema
          schema_fragment = "#/definitions/#{schema_type}"
          case ExJsonSchema.Validator.validate_fragment(resolved_schema, schema_fragment, string_message) do
            :ok -> :ok
            {:error, errors} -> {:error, format_validation_errors(errors)}
          end
        rescue
          e -> {:error, "Validation error: #{inspect(e)}"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Convert a message with atom keys to a message with string keys
  defp message_to_string_keys(message) when is_map(message) do
    Enum.reduce(message, %{}, fn {k, v}, acc ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = message_to_string_keys(v)
      Map.put(acc, key, value)
    end)
  end
  
  defp message_to_string_keys(value) when is_list(value) do
    Enum.map(value, &message_to_string_keys/1)
  end
  
  defp message_to_string_keys(value), do: value

  # Format validation errors for better readability
  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(fn {msg, path} -> "#{path_to_string(path)}: #{msg}" end)
    |> Enum.join(", ")
  end
  
  defp format_validation_errors(error), do: inspect(error)
  
  # Convert JSON schema path to string
  defp path_to_string(path) when is_list(path) do
    Enum.join(path, "/")
  end
  
  defp path_to_string(path), do: inspect(path)

  @doc """
  Validates an initialize request message.

  ## Parameters

  * `message` - The initialize request message to validate

  ## Returns

  * `:ok` - The message is valid
  * `{:error, reason}` - The message is invalid
  """
  @spec validate_initialize_request(map()) :: :ok | {:error, term()}
  def validate_initialize_request(message) do
    validate(message, "InitializeRequest")
  end

  @doc """
  Validates an initialize response message.

  ## Parameters

  * `message` - The initialize response message to validate

  ## Returns

  * `:ok` - The message is valid
  * `{:error, reason}` - The message is invalid
  """
  @spec validate_initialize_result(map()) :: :ok | {:error, term()}
  def validate_initialize_result(message) do
    validate(message, "InitializeResult")
  end
  
  @doc """
  Detects the message type based on its structure.
  
  ## Parameters
  
  * `message` - The message to analyze
  
  ## Returns
  
  * `{:ok, type}` - Successfully detected the message type
  * `{:error, reason}` - Unable to determine the message type
  """
  @spec detect_type(map()) :: {:ok, String.t()} | {:error, term()}
  def detect_type(message) do
    cond do
      # Initialize request
      Map.has_key?(message, :method) and Map.has_key?(message, :id) ->
        method = message.method
        if Map.has_key?(@message_types, method) do
          {:ok, @message_types[method]}
        else
          {:error, "Unknown method: #{method}"}
        end
        
      # Notification (no ID)
      Map.has_key?(message, :method) and not Map.has_key?(message, :id) ->
        method = message.method
        if Map.has_key?(@message_types, method) do
          {:ok, @message_types[method]}
        else
          {:error, "Unknown notification method: #{method}"}
        end
        
      # Response
      Map.has_key?(message, :result) and Map.has_key?(message, :id) ->
        # Special case for initialize response
        if Map.has_key?(get_in(message, [:result]), :serverInfo) do
          {:ok, "InitializeResult"}
        else
          {:ok, "Response"}
        end
        
      # Error
      Map.has_key?(message, :error) and Map.has_key?(message, :id) ->
        {:ok, "ErrorResponse"}
        
      # Unknown
      true ->
        {:error, "Unable to determine message type"}
    end
  end
  
  @doc """
  Validates a message by detecting its type and then validating against the appropriate schema.
  
  ## Parameters
  
  * `message` - The message to validate
  
  ## Returns
  
  * `:ok` - The message is valid
  * `{:error, reason}` - The message is invalid
  """
  @spec validate_message(map()) :: :ok | {:error, term()}
  def validate_message(message) do
    case detect_type(message) do
      {:ok, type} -> validate(message, type)
      {:error, reason} -> {:error, reason}
    end
  end
end