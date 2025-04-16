defmodule MCPEx.Sampling.ResponseTest do
  use ExUnit.Case, async: true

  alias MCPEx.Sampling.Response

  describe "new/5" do
    test "creates valid response" do
      # Create a response
      role = "assistant"
      content = %{type: "text", text: "Hello, I am an assistant"}
      model = "claude-3-sonnet-20240307"
      stop_reason = "endTurn"
      usage = %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      
      {:ok, response} = Response.new(role, content, model, stop_reason, usage)
      
      # Verify response fields
      assert response.role == role
      assert response.content == content
      assert response.model == model
      assert response.stop_reason == stop_reason
      assert response.usage == usage
    end
    
    test "validates role" do
      # Try to create a response with invalid role
      content = %{type: "text", text: "Hello"}
      result = Response.new("user", content, "model", "endTurn")
      
      # Should fail validation
      assert {:error, error} = result
      assert String.contains?(error, "Role must be 'assistant'")
    end
    
    test "validates content type" do
      # Missing type
      invalid_content1 = %{text: "Hello"}
      result1 = Response.new("assistant", invalid_content1, "model", "endTurn")
      assert {:error, error1} = result1
      assert String.contains?(error1, "Content must have a type")
      
      # Invalid type
      invalid_content2 = %{type: "invalid"}
      result2 = Response.new("assistant", invalid_content2, "model", "endTurn")
      assert {:error, error2} = result2
      assert String.contains?(error2, "Content is invalid")
      
      # Text without text field
      invalid_content3 = %{type: "text"}
      result3 = Response.new("assistant", invalid_content3, "model", "endTurn")
      assert {:error, _} = result3
      
      # Image without required fields
      invalid_content4 = %{type: "image", data: "base64data"}
      result4 = Response.new("assistant", invalid_content4, "model", "endTurn")
      assert {:error, _} = result4
    end
    
    test "validates stop reason" do
      content = %{type: "text", text: "Hello"}
      
      # Valid stop reasons
      Enum.each(["endTurn", "maxTokens", "stopSequence", "userRequest"], fn reason ->
        assert {:ok, _} = Response.new("assistant", content, "model", reason)
      end)
      
      # Invalid stop reason
      result = Response.new("assistant", content, "model", "invalid")
      assert {:error, error} = result
      assert String.contains?(error, "Stop reason must be one of")
    end
  end
  
  describe "from_text/4" do
    test "creates a response from text" do
      text = "This is a test response"
      model = "test-model"
      stop_reason = "endTurn"
      
      {:ok, response} = Response.from_text(text, model, stop_reason)
      
      assert response.role == "assistant"
      assert response.content.type == "text"
      assert response.content.text == text
      assert response.model == model
      assert response.stop_reason == stop_reason
    end
    
    test "includes usage when provided" do
      usage = %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      
      {:ok, response} = Response.from_text("Test", "model", "endTurn", usage)
      
      assert response.usage == usage
    end
  end
  
  describe "from_image/5" do
    test "creates a response from image data" do
      data = "base64-encoded-data"
      mime_type = "image/png"
      model = "test-model"
      stop_reason = "endTurn"
      
      {:ok, response} = Response.from_image(data, mime_type, model, stop_reason)
      
      assert response.role == "assistant"
      assert response.content.type == "image"
      assert response.content.data == data
      assert response.content.mime_type == mime_type
      assert response.model == model
      assert response.stop_reason == stop_reason
    end
  end
  
  describe "to_json_rpc/1" do
    test "converts response to JSON-RPC format" do
      # Create a response
      {:ok, response} = Response.from_text("Hello", "test-model", "endTurn")
      
      # Convert to JSON-RPC
      json_rpc = Response.to_json_rpc(response)
      
      # Verify structure and camelCase keys
      assert json_rpc["role"] == "assistant"
      assert json_rpc["content"]["type"] == "text"
      assert json_rpc["content"]["text"] == "Hello"
      assert json_rpc["model"] == "test-model"
      assert json_rpc["stopReason"] == "endTurn"
      refute Map.has_key?(json_rpc, "usage") # No usage in this response
    end
    
    test "includes usage when available" do
      # Create a response with usage
      usage = %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      {:ok, response} = Response.from_text("Hello", "test-model", "endTurn", usage)
      
      # Convert to JSON-RPC
      json_rpc = Response.to_json_rpc(response)
      
      # Verify usage is included with camelCase keys
      assert json_rpc["usage"]["promptTokens"] == 10
      assert json_rpc["usage"]["completionTokens"] == 5
      assert json_rpc["usage"]["totalTokens"] == 15
    end
  end
end