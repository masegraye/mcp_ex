defmodule MCPEx.Sampling.Response do
  @moduledoc """
  Structures and utilities for MCP sampling responses.
  
  This module provides structs and formatting functions for MCP sampling responses
  according to the 2025-03-26 MCP specification.
  """
  
  defstruct [
    :role,
    :content,
    :model,
    :stop_reason,
    :usage
  ]
  
  @type content :: %{
    type: String.t(),
    text: String.t() | nil,
    data: String.t() | nil,
    mime_type: String.t() | nil
  }
  
  @type usage :: %{
    prompt_tokens: integer() | nil,
    completion_tokens: integer() | nil,
    total_tokens: integer() | nil
  }
  
  @type t :: %__MODULE__{
    role: String.t(),
    content: content(),
    model: String.t(),
    stop_reason: String.t(),
    usage: usage() | nil
  }
  
  @valid_stop_reasons [
    "endTurn",      # Natural end of the generation
    "maxTokens",    # Reached maximum token limit
    "stopSequence", # Hit a stop sequence
    "userRequest"   # User requested to stop generation
  ]
  
  @doc """
  Creates a new sampling response struct.
  
  ## Parameters
  
  * `role` - The role of the message (usually "assistant")
  * `content` - The content of the message
  * `model` - The model that generated the response
  * `stop_reason` - The reason generation stopped
  * `usage` - Optional token usage statistics
  
  ## Returns
  
  * `{:ok, response}` - Successfully created response
  * `{:error, reason}` - Failed to create response
  """
  @spec new(String.t(), map(), String.t(), String.t(), map() | nil) :: 
    {:ok, t()} | {:error, term()}
  def new(role, content, model, stop_reason, usage \\ nil) do
    response = %__MODULE__{
      role: role,
      content: content,
      model: model,
      stop_reason: stop_reason,
      usage: usage
    }
    
    case validate_response(response) do
      :ok -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Creates a response from a text string.
  
  ## Parameters
  
  * `text` - The text content
  * `model` - The model that generated the response
  * `stop_reason` - The reason generation stopped
  * `usage` - Optional token usage statistics
  
  ## Returns
  
  * `{:ok, response}` - Successfully created response
  * `{:error, reason}` - Failed to create response
  """
  @spec from_text(String.t(), String.t(), String.t(), map() | nil) ::
    {:ok, t()} | {:error, term()}
  def from_text(text, model, stop_reason, usage \\ nil) do
    content = %{
      type: "text",
      text: text
    }
    
    new("assistant", content, model, stop_reason, usage)
  end
  
  @doc """
  Creates a response from a image data.
  
  ## Parameters
  
  * `data` - The base64-encoded image data
  * `mime_type` - The MIME type of the image
  * `model` - The model that generated the response
  * `stop_reason` - The reason generation stopped
  * `usage` - Optional token usage statistics
  
  ## Returns
  
  * `{:ok, response}` - Successfully created response
  * `{:error, reason}` - Failed to create response
  """
  @spec from_image(String.t(), String.t(), String.t(), String.t(), map() | nil) ::
    {:ok, t()} | {:error, term()}
  def from_image(data, mime_type, model, stop_reason, usage \\ nil) do
    content = %{
      type: "image",
      data: data,
      mime_type: mime_type
    }
    
    new("assistant", content, model, stop_reason, usage)
  end
  
  @doc """
  Converts the response to a JSON-RPC result.
  
  ## Parameters
  
  * `response` - The response to convert
  
  ## Returns
  
  * `map()` - The JSON-RPC result
  """
  @spec to_json_rpc(t()) :: map()
  def to_json_rpc(response) do
    # Convert to JSON-RPC format with camelCase keys
    result = %{
      "role" => response.role,
      "content" => convert_content_to_json(response.content),
      "model" => response.model,
      "stopReason" => response.stop_reason
    }
    
    # Add usage if present
    result = if Map.has_key?(response, :usage) && response.usage do
      Map.put(result, "usage", %{
        "promptTokens" => response.usage[:prompt_tokens],
        "completionTokens" => response.usage[:completion_tokens],
        "totalTokens" => response.usage[:total_tokens]
      })
    else
      result
    end
    
    result
  end
  
  # Private helpers
  
  defp validate_response(response) do
    cond do
      response.role != "assistant" ->
        {:error, "Role must be 'assistant'"}
        
      !is_map(response.content) ->
        {:error, "Content must be a map"}
        
      !Map.has_key?(response.content, :type) ->
        {:error, "Content must have a type"}
        
      !is_content_valid?(response.content) ->
        {:error, "Content is invalid"}
        
      !is_binary(response.model) ->
        {:error, "Model must be a string"}
        
      !is_binary(response.stop_reason) || !stop_reason_valid?(response.stop_reason) ->
        {:error, "Stop reason must be one of: #{Enum.join(@valid_stop_reasons, ", ")}"}
        
      true ->
        :ok
    end
  end
  
  defp is_content_valid?(content) do
    case content[:type] do
      "text" -> is_binary(content[:text])
      "image" -> is_binary(content[:data]) && is_binary(content[:mime_type])
      "audio" -> is_binary(content[:data]) && is_binary(content[:mime_type])
      _ -> false
    end
  end
  
  defp stop_reason_valid?(stop_reason) do
    stop_reason in @valid_stop_reasons
  end
  
  defp convert_content_to_json(content) do
    case content do
      %{type: "text", text: text} ->
        %{
          "type" => "text",
          "text" => text
        }
      
      %{type: "image", data: data, mime_type: mime_type} ->
        %{
          "type" => "image",
          "data" => data,
          "mimeType" => mime_type
        }
      
      %{type: "audio", data: data, mime_type: mime_type} ->
        %{
          "type" => "audio",
          "data" => data,
          "mimeType" => mime_type
        }
    end
  end
end