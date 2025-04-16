defmodule MCPEx.Protocol.JsonRpcTest do
  use ExUnit.Case, async: true

  alias MCPEx.Protocol.JsonRpc
  
  # Helper function to generate a unique ID for tests
  defp generate_test_id, do: System.unique_integer([:positive])

  describe "encode_request/3" do
    test "encodes a valid request" do
      id = 123
      method = "test_method"
      params = %{key: "value"}

      encoded = JsonRpc.encode_request(id, method, params)
      decoded = Jason.decode!(encoded)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == id
      assert decoded["method"] == method
      assert decoded["params"]["key"] == "value"
    end
  end

  describe "encode_notification/2" do
    test "encodes a valid notification" do
      method = "test_notification"
      params = %{key: "value"}

      encoded = JsonRpc.encode_notification(method, params)
      decoded = Jason.decode!(encoded)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == method
      assert decoded["params"]["key"] == "value"
      refute Map.has_key?(decoded, "id")
    end
  end

  describe "encode_response/2" do
    test "encodes a valid response" do
      id = 456
      result = %{result_key: "result_value"}

      encoded = JsonRpc.encode_response(id, result)
      decoded = Jason.decode!(encoded)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == id
      assert decoded["result"]["result_key"] == "result_value"
      refute Map.has_key?(decoded, "error")
    end
  end

  describe "encode_error/2" do
    test "encodes a valid error response" do
      id = 789
      error = %{code: -32600, message: "Invalid Request"}

      encoded = JsonRpc.encode_error(id, error)
      decoded = Jason.decode!(encoded)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == id
      assert decoded["error"]["code"] == -32600
      assert decoded["error"]["message"] == "Invalid Request"
      refute Map.has_key?(decoded, "result")
    end
  end

  describe "decode_message/1" do
    test "decodes a valid request" do
      json = """
      {
        "jsonrpc": "2.0",
        "id": 123,
        "method": "test_method",
        "params": {
          "key": "value"
        }
      }
      """

      assert {:ok, message} = JsonRpc.decode_message(json)
      assert message.jsonrpc == "2.0"
      assert message.id == 123
      assert message.method == "test_method"
      assert message.params.key == "value"
    end

    test "decodes a valid notification" do
      json = """
      {
        "jsonrpc": "2.0",
        "method": "test_notification",
        "params": {
          "key": "value"
        }
      }
      """

      assert {:ok, message} = JsonRpc.decode_message(json)
      assert message.jsonrpc == "2.0"
      assert message.method == "test_notification"
      assert message.params.key == "value"
      refute Map.has_key?(message, :id)
    end

    test "decodes a valid response" do
      json = """
      {
        "jsonrpc": "2.0",
        "id": 456,
        "result": {
          "result_key": "result_value"
        }
      }
      """

      assert {:ok, message} = JsonRpc.decode_message(json)
      assert message.jsonrpc == "2.0"
      assert message.id == 456
      assert message.result.result_key == "result_value"
    end

    test "decodes a valid error" do
      json = """
      {
        "jsonrpc": "2.0",
        "id": 789,
        "error": {
          "code": -32600,
          "message": "Invalid Request"
        }
      }
      """

      assert {:ok, message} = JsonRpc.decode_message(json)
      assert message.jsonrpc == "2.0"
      assert message.id == 789
      assert message.error.code == -32600
      assert message.error.message == "Invalid Request"
    end

    test "returns error for invalid json" do
      json = "{"

      assert {:error, _reason} = JsonRpc.decode_message(json)
    end
  end
  
  describe "encode_batch/1" do
    test "encodes a batch of requests" do
      requests = [
        %{
          jsonrpc: "2.0",
          id: generate_test_id(),
          method: "method1",
          params: %{key1: "value1"}
        },
        %{
          jsonrpc: "2.0", 
          id: generate_test_id(),
          method: "method2",
          params: %{key2: "value2"}
        }
      ]
      
      encoded = JsonRpc.encode_batch(requests)
      decoded = Jason.decode!(encoded)
      
      assert is_list(decoded)
      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["method"] == "method1"
      assert Enum.at(decoded, 1)["method"] == "method2"
    end
    
    test "encodes a batch of notifications" do
      notifications = [
        %{
          jsonrpc: "2.0",
          method: "notification1",
          params: %{key1: "value1"}
        },
        %{
          jsonrpc: "2.0",
          method: "notification2",
          params: %{key2: "value2"}
        }
      ]
      
      encoded = JsonRpc.encode_batch(notifications)
      decoded = Jason.decode!(encoded)
      
      assert is_list(decoded)
      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["method"] == "notification1"
      assert Enum.at(decoded, 1)["method"] == "notification2"
      refute Map.has_key?(Enum.at(decoded, 0), "id")
      refute Map.has_key?(Enum.at(decoded, 1), "id")
    end
    
    test "encodes a mixed batch of requests and notifications" do
      messages = [
        %{
          jsonrpc: "2.0",
          id: generate_test_id(),
          method: "method1",
          params: %{key1: "value1"}
        },
        %{
          jsonrpc: "2.0",
          method: "notification1",
          params: %{key2: "value2"}
        }
      ]
      
      encoded = JsonRpc.encode_batch(messages)
      decoded = Jason.decode!(encoded)
      
      assert is_list(decoded)
      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["method"] == "method1"
      assert Enum.at(decoded, 1)["method"] == "notification1"
      assert Map.has_key?(Enum.at(decoded, 0), "id")
      refute Map.has_key?(Enum.at(decoded, 1), "id")
    end
  end
  
  describe "decode_batch/1" do
    test "decodes a batch of requests" do
      json = """
      [
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "method1",
          "params": {
            "key1": "value1"
          }
        },
        {
          "jsonrpc": "2.0",
          "id": 2,
          "method": "method2",
          "params": {
            "key2": "value2"
          }
        }
      ]
      """
      
      assert {:ok, messages} = JsonRpc.decode_batch(json)
      assert length(messages) == 2
      assert Enum.at(messages, 0).method == "method1"
      assert Enum.at(messages, 1).method == "method2"
      assert Enum.at(messages, 0).id == 1
      assert Enum.at(messages, 1).id == 2
    end
    
    test "decodes a batch of mixed messages" do
      json = """
      [
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "method1",
          "params": {
            "key1": "value1"
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "notification1",
          "params": {
            "key2": "value2"
          }
        },
        {
          "jsonrpc": "2.0",
          "id": 2,
          "result": {
            "key3": "value3"
          }
        }
      ]
      """
      
      assert {:ok, messages} = JsonRpc.decode_batch(json)
      assert length(messages) == 3
      assert Enum.at(messages, 0).method == "method1"
      assert Enum.at(messages, 1).method == "notification1"
      assert Enum.at(messages, 2).result.key3 == "value3"
    end
    
    test "returns error for invalid batch json" do
      json = """
      [
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "method1"
        },
        {
          "jsonrpc": "invalid"
        }
      ]
      """
      
      assert {:error, _reason} = JsonRpc.decode_batch(json)
    end
    
    test "returns error for non-array json" do
      json = """
      {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "method1"
      }
      """
      
      assert {:error, _reason} = JsonRpc.decode_batch(json)
    end
  end
  
  describe "generate_id/0" do
    test "generates a unique ID" do
      id1 = JsonRpc.generate_id()
      id2 = JsonRpc.generate_id()
      
      assert is_integer(id1) or is_binary(id1)
      assert is_integer(id2) or is_binary(id2)
      assert id1 != id2
    end
  end
  
  describe "create_initialize_request/3" do
    test "creates a valid initialize request" do
      client_info = %{name: "TestClient", version: "1.0.0"}
      protocol_version = "2025-03-26"
      capabilities = %{sampling: %{}, roots: %{listChanged: true}}
      
      request = JsonRpc.create_initialize_request(client_info, protocol_version, capabilities)
      
      assert request.jsonrpc == "2.0"
      assert is_integer(request.id) or is_binary(request.id)
      assert request.method == "initialize"
      assert request.params.clientInfo == client_info
      assert request.params.protocolVersion == protocol_version
      assert request.params.capabilities == capabilities
    end
  end
end