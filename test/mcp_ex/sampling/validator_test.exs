defmodule MCPEx.Sampling.ValidatorTest do
  use ExUnit.Case, async: true
  
  alias MCPEx.Sampling.{Validator, Request}
  
  describe "validate_request/2" do
    setup do
      # Create a basic valid request for testing
      valid_request = %Request{
        request_id: "test_123",
        messages: [
          %{
            "role" => "user",
            "content" => %{
              "type" => "text",
              "text" => "Hello, this is a test message."
            }
          }
        ],
        model_preferences: %{
          hints: [],
          cost_priority: 0.5,
          speed_priority: 0.5,
          intelligence_priority: 0.5
        }
      }
      
      {:ok, %{request: valid_request}}
    end
    
    test "returns :ok for valid requests with no options", %{request: request} do
      assert :ok = Validator.validate_request(request)
    end
    
    test "validates message count", %{request: request} do
      # Test with a request under the limit
      assert :ok = Validator.validate_request(request, max_messages: 2)
      
      # Test with a request at the limit
      assert :ok = Validator.validate_request(request, max_messages: 1)
      
      # Test with a request over the limit
      multi_message_request = %{request | messages: List.duplicate(List.first(request.messages), 3)}
      assert {:error, _message} = Validator.validate_request(multi_message_request, max_messages: 2)
    end
    
    test "validates message length", %{request: request} do
      # Test with a message under the limit
      assert :ok = Validator.validate_request(request, max_message_length: 50)
      
      # Test with a message at the limit
      text_length = String.length(request.messages |> List.first() |> get_in(["content", "text"]))
      assert :ok = Validator.validate_request(request, max_message_length: text_length)
      
      # Test with a message over the limit
      assert {:error, _message} = Validator.validate_request(request, max_message_length: 10)
    end
    
    test "validates allowed content types", %{request: request} do
      # Test with text allowed
      assert :ok = Validator.validate_request(request, allowed_content_types: ["text"])
      
      # Test with text not allowed
      assert {:error, _message} = Validator.validate_request(request, allowed_content_types: ["image"])
      
      # Test with multiple types allowed
      assert :ok = Validator.validate_request(request, allowed_content_types: ["text", "image"])
    end
    
    test "validates forbidden patterns", %{request: request} do
      # Test with no matching patterns
      assert :ok = Validator.validate_request(request, forbidden_patterns: [~r/forbidden/, ~r/bad content/])
      
      # Test with a matching pattern
      assert {:error, _message} = Validator.validate_request(request, forbidden_patterns: [~r/test/])
    end
    
    test "runs custom validator", %{request: request} do
      # Test with a passing custom validator
      custom_pass = fn _req, _opts -> :ok end
      assert :ok = Validator.validate_request(request, custom_validator: custom_pass)
      
      # Test with a failing custom validator
      custom_fail = fn _req, _opts -> {:error, "Custom validation failed"} end
      assert {:error, "Custom validation failed"} = Validator.validate_request(request, custom_validator: custom_fail)
    end
  end
  
  describe "filter_request/2" do
    setup do
      # Create a basic request for testing
      request = %Request{
        request_id: "test_123",
        messages: [
          %{
            "role" => "user",
            "content" => %{
              "type" => "text",
              "text" => "This is a secret message with PII: email@example.com and phone 123-456-7890."
            }
          }
        ]
      }
      
      {:ok, %{request: request}}
    end
    
    test "applies length truncation", %{request: request} do
      options = [max_message_length: 20, max_length_truncation: true]
      
      {:ok, filtered} = Validator.filter_request(request, options)
      
      # Check that the message was truncated
      message_text = filtered.messages |> List.first() |> get_in(["content", "text"])
      assert String.length(message_text) > 20  # Account for truncation marker
      assert String.ends_with?(message_text, "... [truncated]")
    end
    
    test "applies pattern redaction", %{request: request} do
      # Define redaction patterns for email and phone number
      options = [
        redact_patterns: [
          {~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}/, "[REDACTED EMAIL]"},
          {~r/\d{3}-\d{3}-\d{4}/, "[REDACTED PHONE]"}
        ]
      ]
      
      {:ok, filtered} = Validator.filter_request(request, options)
      
      # Check that both patterns were redacted
      message_text = filtered.messages |> List.first() |> get_in(["content", "text"])
      assert message_text =~ "[REDACTED EMAIL]"
      assert message_text =~ "[REDACTED PHONE]"
      refute message_text =~ "email@example.com"
      refute message_text =~ "123-456-7890"
    end
    
    test "applies custom filter", %{request: request} do
      # Define a custom filter function
      custom_filter = fn req, _opts ->
        messages = Enum.map(req.messages, fn message ->
          if message["content"]["type"] == "text" do
            text = message["content"]["text"]
            updated_text = String.replace(text, "secret", "FILTERED")
            put_in(message, ["content", "text"], updated_text)
          else
            message
          end
        end)
        
        %{req | messages: messages}
      end
      
      {:ok, filtered} = Validator.filter_request(request, custom_filter: custom_filter)
      
      # Check that the custom filter was applied
      message_text = filtered.messages |> List.first() |> get_in(["content", "text"])
      assert message_text =~ "This is a FILTERED message"
      refute message_text =~ "This is a secret message"
    end
  end
  
  describe "check_rate_limit/2" do
    test "returns :ok when no limits are defined" do
      assert :ok = Validator.check_rate_limit("client_123")
    end
    
    # Note: More complex rate limiting tests would depend on the implementation
    # For now, we're just testing the basic API contract
  end
end