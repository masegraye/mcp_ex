defmodule MCPEx.Sampling.DefaultHandlerTest do
  use ExUnit.Case, async: true

  alias MCPEx.Sampling.DefaultHandler

  describe "default handler" do
    test "returns error response in normal mode" do
      # Setup basic request
      request_id = "req-123"
      messages = [%{role: "user", content: %{type: "text", text: "Hello"}}]
      model_preferences = %{hints: [%{name: "claude-3-sonnet"}]}
      request_options = %{max_tokens: 100}
      handler_config = []
      
      # Call default handler
      result = DefaultHandler.process_sampling_request(
        request_id,
        messages,
        model_preferences,
        request_options,
        handler_config
      )
      
      # Verify it returns an error indicating no LLM integration
      assert {:error, error} = result
      assert Map.has_key?(error, :code)
      assert Map.has_key?(error, :message)
      assert error.code == -32603 # Internal error code
      assert String.contains?(error.message, "No LLM integration configured")
    end
    
    test "returns simulated response in simulator mode" do
      # Setup basic request with simulator_mode
      request_id = "req-456"
      messages = [%{role: "user", content: %{type: "text", text: "Hello"}}]
      model_preferences = %{hints: [%{name: "claude-3-sonnet"}]}
      request_options = %{max_tokens: 100}
      handler_config = [simulator_mode: true]
      
      # Call default handler in simulator mode
      result = DefaultHandler.process_sampling_request(
        request_id,
        messages,
        model_preferences,
        request_options,
        handler_config
      )
      
      # Verify it returns a simulated response
      assert {:ok, response} = result
      assert response.role == "assistant"
      assert response.content.type == "text"
      assert String.contains?(response.content.text, "simulated response")
      assert response.model == "claude-3-sonnet" # Should use the hint
      assert response.stop_reason == "endTurn"
    end
    
    test "handles model preferences correctly" do
      # No model hint
      model_preferences_empty = %{hints: []}
      {:ok, response1} = DefaultHandler.process_sampling_request(
        "req-1", [], model_preferences_empty, %{}, [simulator_mode: true]
      )
      assert response1.model == "simulated-model"
      
      # With model hint
      model_preferences_with_hint = %{hints: [%{name: "test-model"}]}
      {:ok, response2} = DefaultHandler.process_sampling_request(
        "req-2", [], model_preferences_with_hint, %{}, [simulator_mode: true]
      )
      assert response2.model == "test-model"
      
      # With string key hints
      model_preferences_string_keys = %{"hints" => [%{"name" => "string-key-model"}]}
      {:ok, response3} = DefaultHandler.process_sampling_request(
        "req-3", [], model_preferences_string_keys, %{}, [simulator_mode: true]
      )
      assert response3.model == "string-key-model"
    end
  end
end