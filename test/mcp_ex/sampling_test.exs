defmodule MCPEx.SamplingTest do
  use ExUnit.Case, async: true

  alias MCPEx.Sampling
  alias MCPEx.Sampling.Handler

  # Test handler that provides predetermined responses
  defmodule TestHandler do
    @behaviour Handler
    
    @impl true
    def process_sampling_request(request_id, _messages, _model_preferences, _request_options, handler_config) do
      case handler_config[:mode] do
        :success ->
          # Create a response object that will work with to_json_rpc
          {:ok, response} = MCPEx.Sampling.Response.from_text(
            "Test response for #{request_id}",
            "test-model",
            "endTurn"
          )
          {:ok, response}
          
        :error ->
          {:error, %{
            code: -32000,
            message: "Test error"
          }}
          
        :custom_error ->
          {:error, "Simple string error"}
          
        _ ->
          {:error, :unknown_error}
      end
    end
  end

  describe "process_request/3" do
    test "processes a successful request" do
      # Setup
      handler = {TestHandler, [mode: :success]}
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ]
      }
      
      # Process the request
      result = Sampling.process_request(handler, request_id, params)
      
      # Verify result
      assert {:ok, response} = result
      assert response["role"] == "assistant"
      assert response["content"]["type"] == "text"
      assert response["content"]["text"] == "Test response for #{request_id}"
      assert response["model"] == "test-model"
      assert response["stopReason"] == "endTurn"
    end
    
    test "handles handler errors with error map" do
      # Setup with error mode
      handler = {TestHandler, [mode: :error]}
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ]
      }
      
      # Process the request
      result = Sampling.process_request(handler, request_id, params)
      
      # Verify error is returned with code and message
      assert {:error, error} = result
      assert error.code == -32000
      assert error.message == "Test error"
    end
    
    test "handles handler errors with string" do
      # Setup with custom error mode
      handler = {TestHandler, [mode: :custom_error]}
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ]
      }
      
      # Process the request
      result = Sampling.process_request(handler, request_id, params)
      
      # Verify error is converted to standard format
      assert {:error, error} = result
      assert error.code == -32603 # Standard internal error code
      assert error.message == "Simple string error"
    end
    
    test "handles unknown error formats" do
      # Setup with unknown error mode
      handler = {TestHandler, [mode: :unknown]}
      request_id = "req-123"
      params = %{
        "messages" => [
          %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
        ]
      }
      
      # Process the request
      result = Sampling.process_request(handler, request_id, params)
      
      # Verify error is converted to standard format
      assert {:error, error} = result
      assert error.code == -32603 # Standard internal error code
      assert String.contains?(error.message, "Sampling request failed")
    end
    
    test "handles invalid requests" do
      # Setup with valid handler but invalid request
      handler = {TestHandler, [mode: :success]}
      request_id = "req-123"
      params = %{
        "messages" => [] # Invalid: empty messages
      }
      
      # Process the request
      result = Sampling.process_request(handler, request_id, params)
      
      # Verify validation error is returned
      assert {:error, error} = result
      assert error.code == -32602 # Invalid params
      assert String.contains?(error.message, "Invalid sampling request")
    end
  end
  
  describe "parse_handler/1" do
    test "handles module without config" do
      # Direct module reference
      result = Sampling.default_handler()
      
      # Should return tuple with handler module and empty config
      assert is_tuple(result)
      assert tuple_size(result) == 2
      assert is_atom(elem(result, 0))
      assert is_list(elem(result, 1))
    end
  end
end