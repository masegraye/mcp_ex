defmodule MCPEx.Protocol.SchemasTest do
  use ExUnit.Case, async: true

  alias MCPEx.Protocol.Schemas

  describe "detect_type/1" do
    test "detects initialize request" do
      message = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          clientInfo: %{name: "TestClient", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      assert {:ok, "InitializeRequest"} = Schemas.detect_type(message)
    end
    
    test "detects initialize response" do
      message = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert {:ok, "InitializeResult"} = Schemas.detect_type(message)
    end
    
    test "detects initialized notification" do
      message = %{
        jsonrpc: "2.0",
        method: "notifications/initialized",
        params: %{}
      }
      
      assert {:ok, "InitializedNotification"} = Schemas.detect_type(message)
    end
    
    test "detects error" do
      message = %{
        jsonrpc: "2.0",
        id: 1,
        error: %{
          code: -32600,
          message: "Invalid Request"
        }
      }
      
      assert {:ok, "ErrorResponse"} = Schemas.detect_type(message)
    end
    
    test "returns error for unknown message type" do
      message = %{
        jsonrpc: "2.0",
        method: "unknown/method",
        params: %{}
      }
      
      assert {:error, _reason} = Schemas.detect_type(message)
    end
  end
  
  describe "validate/2" do
    test "validates valid initialize request" do
      message = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          clientInfo: %{name: "TestClient", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      assert :ok = Schemas.validate(message, "InitializeRequest")
    end
    
    test "returns error for invalid initialize request" do
      # Missing required clientInfo field
      message = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      assert {:error, _reason} = Schemas.validate(message, "InitializeRequest")
    end
    
    test "validates valid resource read request" do
      message = %{
        jsonrpc: "2.0",
        id: 2,
        method: "resources/read",
        params: %{
          uri: "file:///test.txt"
        }
      }
      
      assert :ok = Schemas.validate(message, "ReadResourceRequest")
    end
    
    test "returns error for invalid resource read request" do
      # Missing required uri field
      message = %{
        jsonrpc: "2.0",
        id: 2,
        method: "resources/read",
        params: %{}
      }
      
      assert {:error, _reason} = Schemas.validate(message, "ReadResourceRequest")
    end
  end
  
  describe "validate_message/1" do
    test "validates a message by detecting its type" do
      message = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          clientInfo: %{name: "TestClient", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      assert :ok = Schemas.validate_message(message)
    end
    
    test "returns error for invalid message" do
      # Missing required clientInfo field
      message = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      assert {:error, _reason} = Schemas.validate_message(message)
    end
    
    test "returns error for undetectable message type" do
      message = %{
        jsonrpc: "2.0",
        method: "unknown/method",
        params: %{}
      }
      
      assert {:error, _reason} = Schemas.validate_message(message)
    end
  end
end