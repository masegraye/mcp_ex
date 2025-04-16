defmodule MCPEx.Sampling.Validator do
  @moduledoc """
  Content validation and filtering for MCP sampling requests.
  
  This module provides utilities for validating and filtering content in sampling
  requests to enforce security policies, content guidelines, and rate limits.
  """
  
  alias MCPEx.Sampling.Request
  require Logger
  
  @doc """
  Validates a sampling request against security policies and content guidelines.
  
  ## Parameters
  
  * `request` - The sampling request to validate
  * `options` - Validation options
  
  ## Options
  
  * `:max_message_length` - Maximum length of any message in characters
  * `:max_messages` - Maximum number of messages allowed in a request
  * `:allowed_content_types` - List of allowed content types (e.g., ["text", "image"])
  * `:forbidden_patterns` - List of regex patterns to reject in text content
  * `:custom_validator` - Function taking (request, options) and returning :ok or {:error, reason}
  
  ## Returns
  
  * `:ok` - The request passes all validation checks
  * `{:error, reason}` - The request failed validation
  """
  @spec validate_request(Request.t(), keyword()) :: :ok | {:error, term()}
  def validate_request(request, options \\ []) do
    with :ok <- validate_message_count(request, options),
         :ok <- validate_message_length(request, options),
         :ok <- validate_content_types(request, options),
         :ok <- validate_forbidden_patterns(request, options),
         :ok <- run_custom_validator(request, options) do
      :ok
    end
  end
  
  @doc """
  Applies content filtering to a request, modifying or redacting content as needed.
  
  ## Parameters
  
  * `request` - The sampling request to filter
  * `options` - Filtering options
  
  ## Options
  
  * `:redact_patterns` - List of {regex, replacement} tuples to apply to text content
  * `:max_length_truncation` - If true, truncate messages that exceed max length
  * `:custom_filter` - Function taking (request, options) and returning filtered request
  
  ## Returns
  
  * `{:ok, filtered_request}` - The filtered request
  * `{:error, reason}` - Failed to filter the request
  """
  @spec filter_request(Request.t(), keyword()) :: {:ok, Request.t()} | {:error, term()}
  def filter_request(request, options \\ []) do
    try do
      filtered_request = request
        |> apply_length_truncation(options)
        |> apply_pattern_redaction(options)
        |> apply_custom_filter(options)
      
      {:ok, filtered_request}
    rescue
      e ->
        Logger.error("Error filtering request: #{inspect(e)}")
        {:error, "Failed to filter request: #{inspect(e)}"}
    end
  end
  
  @doc """
  Checks if a client should be rate limited based on request history.
  
  ## Parameters
  
  * `client_id` - Identifier for the client
  * `options` - Rate limiting options
  
  ## Options
  
  * `:requests_per_minute` - Maximum requests allowed per minute
  * `:requests_per_hour` - Maximum requests allowed per hour
  * `:requests_per_day` - Maximum requests allowed per day
  * `:store` - Module to use for tracking request history
  
  ## Returns
  
  * `:ok` - The client is within rate limits
  * `{:error, reason}` - The client should be rate limited
  """
  @spec check_rate_limit(String.t(), keyword()) :: :ok | {:error, term()}
  def check_rate_limit(_client_id, _options \\ []) do
    # Implementation placeholder
    # In a real implementation, this would use a state store to track request history
    # and enforce rate limits based on configured thresholds.
    :ok
  end
  
  # Private validation helpers
  
  defp validate_message_count(request, options) do
    max_messages = Keyword.get(options, :max_messages)
    
    if max_messages && length(request.messages) > max_messages do
      {:error, "Request exceeds maximum message count of #{max_messages}"}
    else
      :ok
    end
  end
  
  defp validate_message_length(request, options) do
    max_length = Keyword.get(options, :max_message_length)
    
    if max_length do
      Enum.find_value(request.messages, :ok, fn message ->
        content = message["content"]
        
        case content["type"] do
          "text" ->
            text = content["text"] || ""
            if String.length(text) > max_length do
              {:error, "Message exceeds maximum length of #{max_length} characters"}
            else
              false
            end
            
          _ -> false
        end
      end)
    else
      :ok
    end
  end
  
  defp validate_content_types(request, options) do
    allowed_types = Keyword.get(options, :allowed_content_types)
    
    if allowed_types do
      Enum.find_value(request.messages, :ok, fn message ->
        content = message["content"]
        type = content["type"]
        
        if type not in allowed_types do
          {:error, "Content type '#{type}' is not allowed"}
        else
          false
        end
      end)
    else
      :ok
    end
  end
  
  defp validate_forbidden_patterns(request, options) do
    patterns = Keyword.get(options, :forbidden_patterns, [])
    
    if patterns != [] do
      Enum.find_value(request.messages, :ok, fn message ->
        content = message["content"]
        
        if content["type"] == "text" do
          text = content["text"] || ""
          
          Enum.find_value(patterns, false, fn pattern ->
            if Regex.match?(pattern, text) do
              {:error, "Content contains forbidden pattern"}
            else
              false
            end
          end)
        else
          false
        end
      end)
    else
      :ok
    end
  end
  
  defp run_custom_validator(request, options) do
    custom_validator = Keyword.get(options, :custom_validator)
    
    if is_function(custom_validator, 2) do
      custom_validator.(request, options)
    else
      :ok
    end
  end
  
  # Private filtering helpers
  
  defp apply_length_truncation(request, options) do
    max_length = Keyword.get(options, :max_message_length)
    should_truncate = Keyword.get(options, :max_length_truncation, false)
    
    if max_length && should_truncate do
      messages = Enum.map(request.messages, fn message ->
        content = message["content"]
        
        if content["type"] == "text" do
          text = content["text"] || ""
          
          if String.length(text) > max_length do
            truncated_text = String.slice(text, 0, max_length) <> "... [truncated]"
            updated_content = Map.put(content, "text", truncated_text)
            Map.put(message, "content", updated_content)
          else
            message
          end
        else
          message
        end
      end)
      
      %{request | messages: messages}
    else
      request
    end
  end
  
  defp apply_pattern_redaction(request, options) do
    patterns = Keyword.get(options, :redact_patterns, [])
    
    if patterns != [] do
      messages = Enum.map(request.messages, fn message ->
        content = message["content"]
        
        if content["type"] == "text" do
          text = content["text"] || ""
          
          redacted_text = Enum.reduce(patterns, text, fn {pattern, replacement}, acc ->
            Regex.replace(pattern, acc, replacement)
          end)
          
          updated_content = Map.put(content, "text", redacted_text)
          Map.put(message, "content", updated_content)
        else
          message
        end
      end)
      
      %{request | messages: messages}
    else
      request
    end
  end
  
  defp apply_custom_filter(request, options) do
    custom_filter = Keyword.get(options, :custom_filter)
    
    if is_function(custom_filter, 2) do
      custom_filter.(request, options)
    else
      request
    end
  end
end