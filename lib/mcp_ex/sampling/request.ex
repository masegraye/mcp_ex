defmodule MCPEx.Sampling.Request do
  @moduledoc """
  Structures and utilities for MCP sampling requests.
  
  This module provides structs and validation functions for MCP sampling requests
  according to the 2025-03-26 MCP specification.
  """

  @doc """
  Represents an MCP sampling request with all associated data.
  
  Fields:
  * `request_id` - The JSON-RPC request ID for correlation
  * `messages` - The conversation history to send to the LLM
  * `model_preferences` - Model selection preferences
  * `system_prompt` - Optional system prompt to use
  * `max_tokens` - Optional maximum number of tokens to generate
  * `stop_sequences` - Optional sequences that will stop generation
  * `temperature` - Optional temperature for sampling (0.0-1.0)
  * `top_p` - Optional nucleus sampling parameter (0.0-1.0)
  * `top_k` - Optional top-k sampling parameter
  """
  defstruct [
    :request_id,
    :messages,
    :model_preferences,
    :system_prompt,
    :max_tokens,
    :stop_sequences,
    :temperature,
    :top_p,
    :top_k
  ]

  @type message :: %{
    role: String.t(),
    content: content()
  }

  @type content :: %{
    type: String.t(),
    text: String.t() | nil,
    data: String.t() | nil,
    mime_type: String.t() | nil
  }

  @type model_hint :: %{
    name: String.t()
  }

  @type model_preferences :: %{
    hints: [model_hint()],
    cost_priority: float() | nil,
    speed_priority: float() | nil,
    intelligence_priority: float() | nil
  }

  @type t :: %__MODULE__{
    request_id: String.t(),
    messages: [message()],
    model_preferences: model_preferences(),
    system_prompt: String.t() | nil,
    max_tokens: integer() | nil,
    stop_sequences: [String.t()] | nil,
    temperature: float() | nil,
    top_p: float() | nil,
    top_k: integer() | nil
  }

  @doc """
  Creates a new sampling request struct from a JSON-RPC request.
  
  ## Parameters
  
  * `request_id` - The JSON-RPC request ID
  * `params` - The params field from the JSON-RPC request
  
  ## Returns
  
  * `{:ok, request}` - Successfully parsed request
  * `{:error, reason}` - Failed to parse request
  """
  @spec from_json_rpc(String.t(), map()) :: {:ok, t()} | {:error, term()}
  def from_json_rpc(request_id, params) do
    try do
      request = %__MODULE__{
        request_id: request_id,
        messages: Map.get(params, "messages"),
        model_preferences: normalize_model_preferences(Map.get(params, "modelPreferences", %{})),
        system_prompt: Map.get(params, "systemPrompt"),
        max_tokens: Map.get(params, "maxTokens"),
        stop_sequences: Map.get(params, "stopSequences"),
        temperature: Map.get(params, "temperature"),
        top_p: Map.get(params, "topP"),
        top_k: Map.get(params, "topK")
      }
      
      # Basic validation
      case validate_request(request) do
        :ok -> {:ok, request}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, "Failed to parse sampling request: #{inspect(e)}"}
    end
  end
  
  @doc """
  Validates a sampling request for correctness.
  
  ## Parameters
  
  * `request` - The request to validate
  
  ## Returns
  
  * `:ok` - The request is valid
  * `{:error, reason}` - The request is invalid
  """
  @spec validate_request(t()) :: :ok | {:error, term()}
  def validate_request(request) do
    cond do
      !request.messages || !is_list(request.messages) || Enum.empty?(request.messages) ->
        {:error, "Messages must be a non-empty list"}
        
      !all_messages_valid?(request.messages) ->
        {:error, "One or more messages are invalid"}
        
      !is_nil(request.temperature) && (request.temperature < 0.0 || request.temperature > 1.0) ->
        {:error, "Temperature must be between 0.0 and 1.0"}
        
      !is_nil(request.top_p) && (request.top_p < 0.0 || request.top_p > 1.0) ->
        {:error, "Top-p must be between 0.0 and 1.0"}
        
      !is_nil(request.top_k) && request.top_k < 1 ->
        {:error, "Top-k must be at least 1"}
        
      !is_nil(request.max_tokens) && request.max_tokens < 1 ->
        {:error, "Max tokens must be at least 1"}
        
      true ->
        :ok
    end
  end
  
  # Private helpers

  defp all_messages_valid?(messages) do
    Enum.all?(messages, fn message ->
      is_map(message) &&
      Map.has_key?(message, "role") &&
      Map.has_key?(message, "content") &&
      is_content_valid?(message["content"])
    end)
  end
  
  defp is_content_valid?(content) do
    is_map(content) &&
    Map.has_key?(content, "type") &&
    case content["type"] do
      "text" -> Map.has_key?(content, "text")
      "image" -> Map.has_key?(content, "data") && Map.has_key?(content, "mimeType")
      "audio" -> Map.has_key?(content, "data") && Map.has_key?(content, "mimeType")
      _ -> false
    end
  end
  
  defp normalize_model_preferences(prefs) do
    hints = Map.get(prefs, "hints", [])
    
    %{
      hints: hints,
      cost_priority: Map.get(prefs, "costPriority"),
      speed_priority: Map.get(prefs, "speedPriority"),
      intelligence_priority: Map.get(prefs, "intelligencePriority")
    }
  end
end