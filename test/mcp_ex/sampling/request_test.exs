defmodule MCPEx.Sampling.RequestTest do
  use ExUnit.Case, async: true

  alias MCPEx.Sampling.Request

  describe "from_json_rpc/2" do
    test "parses a valid request" do
      # Setup a valid JSON-RPC request
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello world"}}
        ],
        "modelPreferences" => %{
          "hints" => [%{"name" => "claude-3-sonnet"}],
          "intelligencePriority" => 0.8,
          "speedPriority" => 0.5,
          "costPriority" => 0.3
        },
        "systemPrompt" => "You are a helpful assistant",
        "maxTokens" => 1000,
        "temperature" => 0.7
      }
      
      # Parse the request
      {:ok, request} = Request.from_json_rpc(request_id, params)
      
      # Verify struct fields
      assert request.request_id == request_id
      assert length(request.messages) == 1
      assert hd(request.messages)["role"] == "user"
      assert hd(request.messages)["content"]["text"] == "Hello world"
      
      # Verify model preferences are normalized
      assert hd(request.model_preferences.hints)["name"] == "claude-3-sonnet"
      assert request.model_preferences.intelligence_priority == 0.8
      assert request.model_preferences.speed_priority == 0.5
      assert request.model_preferences.cost_priority == 0.3
      
      # Verify other options
      assert request.system_prompt == "You are a helpful assistant"
      assert request.max_tokens == 1000
      assert request.temperature == 0.7
    end
    
    test "validates messages" do
      # Setup a request with empty messages
      request_id = "req-123"
      params = %{
        "messages" => []
      }
      
      # Parse the request - should fail validation
      result = Request.from_json_rpc(request_id, params)
      assert {:error, error} = result
      assert String.contains?(error, "Messages must be a non-empty list")
      
      # Setup a request with invalid message content
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "invalid"}}
        ]
      }
      
      # Parse the request - should fail validation
      result = Request.from_json_rpc(request_id, params)
      assert {:error, error} = result
      assert String.contains?(error, "One or more messages are invalid")
    end
    
    test "validates temperature" do
      # Setup a request with invalid temperature (too high)
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "temperature" => 2.0 # Invalid: should be between 0 and 1
      }
      
      # Parse the request - should fail validation
      result = Request.from_json_rpc(request_id, params)
      assert {:error, error} = result
      assert String.contains?(error, "Temperature must be between 0.0 and 1.0")
      
      # Test with valid temperatures
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "temperature" => 0.5 # Valid
      }
      
      # Parse the request - should succeed
      result = Request.from_json_rpc(request_id, params)
      assert {:ok, _request} = result
    end
    
    test "validates top_p" do
      # Setup a request with invalid top_p (negative)
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "topP" => -0.5 # Invalid: should be between 0 and 1
      }
      
      # Parse the request - should fail validation
      result = Request.from_json_rpc(request_id, params)
      assert {:error, error} = result
      assert String.contains?(error, "Top-p must be between 0.0 and 1.0")
    end
    
    test "validates max_tokens" do
      # Setup a request with invalid max_tokens (zero)
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ],
        "maxTokens" => 0 # Invalid: should be at least 1
      }
      
      # Parse the request - should fail validation
      result = Request.from_json_rpc(request_id, params)
      assert {:error, error} = result
      assert String.contains?(error, "Max tokens must be at least 1")
    end
  end
  
  describe "validate_request/1" do
    test "handles different types of content" do
      # Text content
      text_message = %{
        "role" => "user",
        "content" => %{"type" => "text", "text" => "Hello"}
      }
      
      # Image content
      image_message = %{
        "role" => "user",
        "content" => %{"type" => "image", "data" => "base64data", "mimeType" => "image/jpeg"}
      }
      
      # Audio content
      audio_message = %{
        "role" => "user",
        "content" => %{"type" => "audio", "data" => "base64data", "mimeType" => "audio/wav"}
      }
      
      # Create a request with mixed content
      request = %Request{
        request_id: "req-123",
        messages: [text_message, image_message, audio_message],
        model_preferences: %{hints: []}
      }
      
      # Validate the request
      assert :ok = Request.validate_request(request)
    end
  end
end