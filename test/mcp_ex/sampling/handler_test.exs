defmodule MCPEx.Sampling.HandlerTest do
  use ExUnit.Case, async: true

  alias MCPEx.Sampling.Handler

  # Define a mock handler for testing
  defmodule MockHandler do
    @behaviour Handler
    
    @impl true
    def process_sampling_request(request_id, messages, model_preferences, request_options, handler_config) do
      # Echo back the inputs as a map for verification
      # In a real handler, this would process the request and return a response
      response = %{
        role: "assistant",
        content: %{
          type: "text",
          text: "Mock response for request #{request_id}"
        },
        model: get_model_name(model_preferences),
        stop_reason: "endTurn"
      }
      
      # If test_mode is set in handler_config, return the inputs for testing
      if handler_config[:test_mode] do
        {:ok, %{
          inputs: %{
            request_id: request_id,
            messages: messages,
            model_preferences: model_preferences,
            request_options: request_options,
            handler_config: handler_config
          },
          response: response
        }}
      else
        {:ok, response}
      end
    end
    
    # Helper to extract model name from preferences
    defp get_model_name(preferences) do
      case get_in(preferences, [:hints]) do
        nil -> "mock-model"
        [] -> "mock-model"
        hints ->
          case List.first(hints) do
            %{name: name} -> name
            _ -> "mock-model"
          end
      end
    end
  end
  
  describe "handler behavior" do
    test "callback definition is correct" do
      # Verify the callback function is defined correctly
      callbacks = Handler.behaviour_info(:callbacks)
      assert {:process_sampling_request, 5} in callbacks
    end
    
    test "mock handler implements the behavior correctly" do
      # Basic test to verify our mock handler works
      request_id = "test-123"
      messages = [%{role: "user", content: %{type: "text", text: "Hello"}}]
      model_preferences = %{hints: [%{name: "test-model"}]}
      request_options = %{max_tokens: 100}
      handler_config = [test_mode: true]
      
      # Call the handler
      {:ok, result} = MockHandler.process_sampling_request(
        request_id, 
        messages, 
        model_preferences, 
        request_options, 
        handler_config
      )
      
      # Verify all parameters were passed correctly
      assert result.inputs.request_id == request_id
      assert result.inputs.messages == messages
      assert result.inputs.model_preferences == model_preferences
      assert result.inputs.request_options == request_options
      assert result.inputs.handler_config == handler_config
      
      # Verify response structure
      assert result.response.role == "assistant"
      assert result.response.content.type == "text"
      assert result.response.model == "test-model"
      assert result.response.stop_reason == "endTurn"
    end
  end
end