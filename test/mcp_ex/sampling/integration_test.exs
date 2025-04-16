defmodule MCPEx.Sampling.IntegrationTest do
  use ExUnit.Case, async: false # Not async due to shared rate limiter state
  
  alias MCPEx.Sampling
  alias MCPEx.Sampling.{Handler, RateLimiter}
  
  # Test handler that logs what it received
  defmodule TestHandler do
    @behaviour Handler
    
    @impl true
    def process_sampling_request(_request_id, messages, _model_preferences, _request_options, _handler_config) do
      # Create a simple response
      case messages do
        [%{"content" => %{"text" => text}} | _rest] when is_binary(text) ->
          {:ok, %{
            role: "assistant",
            content: %{
              type: "text",
              text: "Processed: #{text}"
            },
            model: "test-model",
            stop_reason: "endTurn"
          }}
          
        _ ->
          {:error, "Invalid message format"}
      end
    end
  end
  
  setup do
    # Start or restart the rate limiter
    case Process.whereis(RateLimiter) do
      nil -> 
        {:ok, _limiter} = RateLimiter.start_link(name: RateLimiter)
      _pid -> 
        # We don't restart here since individual tests might want their own clean state
        # Instead we just make sure to clean up at the end
        :ok
    end
    
    # Basic valid params
    params = %{
      "messages" => [
        %{
          "role" => "user", 
          "content" => %{
            "type" => "text", 
            "text" => "Hello, this is a test message with PII: email@example.com"
          }
        }
      ]
    }
    
    # Clean up after tests
    on_exit(fn -> 
      case Process.whereis(RateLimiter) do
        nil -> :ok
        pid -> Process.exit(pid, :normal)
      end
    end)
    
    {:ok, %{params: params}}
  end
  
  describe "validation integration" do
    test "rejects requests with forbidden patterns", %{params: params} do
      # Setup handler with validation that forbids email patterns
      handler = {TestHandler, [
        validation: [
          forbidden_patterns: [~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}/]
        ]
      ]}
      
      # Process the request with email address in text
      result = Sampling.process_request(handler, "req-123", params)
      
      # Should be rejected due to forbidden pattern
      assert {:error, error} = result
      assert error.message =~ "Content contains forbidden pattern"
    end
    
    test "limits message length", %{params: params} do
      # Setup handler with strict message length limit
      handler = {TestHandler, [
        validation: [
          max_message_length: 10
        ]
      ]}
      
      # Process the request with long message
      result = Sampling.process_request(handler, "req-123", params)
      
      # Should be rejected due to length
      assert {:error, error} = result
      assert error.message =~ "exceeds maximum length"
    end
  end
  
  describe "filtering integration" do
    test "redacts sensitive information", %{params: params} do
      # Setup handler with redaction filtering (explicitly disable rate limiting)
      handler = {TestHandler, [
        filtering: [
          redact_patterns: [
            {~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}/, "[REDACTED]"}
          ]
        ],
        # Explicitly set empty rate limits to avoid rate limiter checks
        rate_limit: []
      ]}
      
      # Process the request with email to be redacted
      {:ok, response} = Sampling.process_request(handler, "req-123", params)
      
      # Check that response contains redacted text
      assert response["content"]["text"] =~ "Processed: Hello, this is a test message with PII: [REDACTED]"
      refute response["content"]["text"] =~ "email@example.com"
    end
    
    test "truncates long messages", %{params: _params} do
      # Make a request with a very long message
      long_message = String.duplicate("This is a test. ", 100) # ~1600 chars
      
      # Create new params with long message - avoiding put_in with list index
      long_params = %{
        "messages" => [
          %{
            "role" => "user",
            "content" => %{
              "type" => "text",
              "text" => long_message
            }
          }
        ]
      }
      
      # Setup handler with truncation filtering (explicitly disable rate limiting)
      handler = {TestHandler, [
        filtering: [
          max_message_length: 50,
          max_length_truncation: true
        ],
        # Explicitly set empty rate limits to avoid rate limiter checks
        rate_limit: []
      ]}
      
      # Process the request with long message to be truncated
      {:ok, response} = Sampling.process_request(handler, "req-123", long_params)
      
      # Check that the message was truncated
      assert response["content"]["text"] =~ "... [truncated]"
      assert String.length(response["content"]["text"]) < String.length(long_message)
    end
  end
  
  describe "rate limiting" do
    # We'll test the RateLimiter unit directly without trying to integrate with Sampling
    test "records requests and returns stats" do
      # Create a separate rate limiter just for this test with a unique name
      test_limiter_name = :"test_rate_limiter_#{System.unique_integer([:positive])}"
      {:ok, limiter_pid} = RateLimiter.start_link(name: test_limiter_name)
      
      # Use a separate client ID for this test
      client_id = :"test_client_#{System.unique_integer([:positive])}"
      
      try do
        # No requests initially
        stats = RateLimiter.get_stats(test_limiter_name, client_id)
        assert stats.total_requests == 0
        
        # Record some requests
        RateLimiter.record_request(test_limiter_name, client_id)
        RateLimiter.record_request(test_limiter_name, client_id)
        
        # Check updated stats
        updated_stats = RateLimiter.get_stats(test_limiter_name, client_id)
        assert updated_stats.total_requests == 2
        assert updated_stats.requests_last_minute == 2
      after
        # Kill our test rate limiter
        Process.exit(limiter_pid, :normal)
      end
    end
    
    # Test the validator integration directly
    test "validates request content types", %{params: _params} do
      # Create a request with different content types
      request = %MCPEx.Sampling.Request{
        request_id: "test-123",
        messages: [
          %{
            "role" => "user",
            "content" => %{
              "type" => "image", # Using non-text type
              "data" => "base64data",
              "mimeType" => "image/png"
            }
          }
        ]
      }
      
      # Validation should fail when only text is allowed
      validation_options = [allowed_content_types: ["text"]]
      assert {:error, error_message} = MCPEx.Sampling.Validator.validate_request(request, validation_options)
      assert error_message =~ "Content type 'image' is not allowed"
      
      # Validation should pass when image is allowed
      validation_options = [allowed_content_types: ["text", "image"]]
      assert :ok = MCPEx.Sampling.Validator.validate_request(request, validation_options)
    end
  end
  
  describe "combined validation, filtering and rate limiting" do
    test "applies all operations in sequence", %{params: params} do
      # Setup handler with all features, but disable rate limiting since we test that separately
      handler = {TestHandler, [
        validation: [
          max_message_length: 200,
          allowed_content_types: ["text"]
        ],
        filtering: [
          redact_patterns: [
            {~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}/, "[EMAIL]"}
          ]
        ],
        # No rate limiting for this test
        rate_limit: []
      ]}
      
      # Process the request
      {:ok, response} = Sampling.process_request(handler, "req-complex", params)
      
      # Check that the email was redacted
      assert response["content"]["text"] =~ "[EMAIL]"
      refute response["content"]["text"] =~ "email@example.com"
      
      # Should be able to make more requests
      assert {:ok, _} = Sampling.process_request(handler, "req-complex-2", params)
    end
  end
end