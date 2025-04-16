defmodule MCPEx.Protocol.ErrorsTest do
  use ExUnit.Case, async: true
  
  alias MCPEx.Protocol.Errors
  
  describe "create_error/3" do
    test "creates an error object with code and message" do
      code = -32600
      message = "Invalid Request"
      
      error = Errors.create_error(code, message)
      
      assert error.code == code
      assert error.message == message
      refute Map.has_key?(error, :data)
    end
    
    test "includes optional data when provided" do
      code = -32600
      message = "Invalid Request"
      data = %{field: "test", details: "missing parameter"}
      
      error = Errors.create_error(code, message, data)
      
      assert error.code == code
      assert error.message == message
      assert error.data == data
    end
  end
  
  describe "standard error functions" do
    test "parse_error/1 creates error with correct code" do
      error = Errors.parse_error("Parse error details")
      
      assert error.code == -32700
      assert error.message == "Parse error details"
    end
    
    test "parse_error/0 creates error with default message" do
      error = Errors.parse_error()
      
      assert error.code == -32700
      assert error.message == "Parse error"
    end
    
    test "invalid_request/1 creates error with correct code" do
      error = Errors.invalid_request("Invalid request details")
      
      assert error.code == -32600
      assert error.message == "Invalid request details"
    end
    
    test "method_not_found/1 creates error with correct code" do
      error = Errors.method_not_found("unknown_method")
      
      assert error.code == -32601
      assert error.message == "Method not found: unknown_method"
    end
    
    test "invalid_params/1 creates error with correct code" do
      error = Errors.invalid_params("Missing required parameter")
      
      assert error.code == -32602
      assert error.message == "Invalid params: Missing required parameter"
    end
    
    test "internal_error/1 creates error with correct code" do
      error = Errors.internal_error("Unexpected server error")
      
      assert error.code == -32603
      assert error.message == "Internal error: Unexpected server error"
    end
  end
  
  describe "MCP-specific errors" do
    test "request_cancelled/1 creates error with correct code" do
      error = Errors.request_cancelled("Client cancelled request")
      
      assert error.code == -32800
      assert error.message == "Request cancelled: Client cancelled request"
    end
    
    test "content_too_large/1 creates error with correct code" do
      error = Errors.content_too_large("Message exceeds size limit")
      
      assert error.code == -32801
      assert error.message == "Content too large: Message exceeds size limit"
    end
  end
  
  describe "encode_error_response/2" do
    test "encodes an error response with an ID" do
      id = 123
      error = Errors.invalid_request("Test error")
      
      response = Errors.encode_error_response(id, error)
      
      assert response.jsonrpc == "2.0"
      assert response.id == id
      assert response.error == error
    end
    
    test "encodes an error response for a notification (null ID)" do
      error = Errors.invalid_request("Test error")
      
      response = Errors.encode_error_response(nil, error)
      
      assert response.jsonrpc == "2.0"
      assert response.id == nil
      assert response.error == error
    end
  end
  
  describe "error_response_json/2" do
    test "returns JSON string for error response" do
      id = 456
      error = Errors.method_not_found("test_method")
      
      json = Errors.error_response_json(id, error)
      
      decoded = Jason.decode!(json)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == id
      assert decoded["error"]["code"] == -32601
      assert decoded["error"]["message"] == "Method not found: test_method"
    end
  end
  
  describe "handle_error/1" do
    test "formats standard JSON-RPC errors" do
      jason_error = %Jason.DecodeError{position: 5, data: "{invalid"}
      
      error_result = Errors.handle_error(jason_error)
      
      assert {:error, error} = error_result
      assert error.code == -32700
      assert String.contains?(error.message, "Parse error")
    end
    
    test "formats timeout errors" do
      error_result = Errors.handle_error({:error, :timeout})
      
      assert {:error, error} = error_result
      assert error.code == -32000
      assert String.contains?(error.message, "Request timed out")
    end
    
    test "formats generic errors" do
      error_result = Errors.handle_error("Unknown error")
      
      assert {:error, error} = error_result
      assert error.code == -32603
      assert String.contains?(error.message, "Internal error")
    end
  end
end