defmodule MCPEx.Protocol.TypesTest do
  use ExUnit.Case, async: true
  
  alias MCPEx.Protocol.Types
  alias MCPEx.Protocol.Types.{
    InitializeRequest,
    InitializeResult,
    InitializedNotification,
    ReadResourceRequest,
    ResourceContent
  }
  
  describe "InitializeRequest" do
    test "creates valid initialize request from struct" do
      client_info = %{name: "TestClient", version: "1.0.0"}
      protocol_version = "2025-03-26"
      capabilities = %{sampling: %{}, roots: %{listChanged: true}}
      
      request = %InitializeRequest{
        id: 1,
        client_info: client_info,
        protocol_version: protocol_version,
        capabilities: capabilities
      }
      
      assert request.id == 1
      assert request.client_info == client_info
      assert request.protocol_version == protocol_version
      assert request.capabilities == capabilities
    end
    
    test "converts struct to map" do
      request = %InitializeRequest{
        id: 1,
        client_info: %{name: "TestClient", version: "1.0.0"},
        protocol_version: "2025-03-26",
        capabilities: %{sampling: %{}}
      }
      
      map = Types.to_map(request)
      
      assert is_map(map)
      assert map.jsonrpc == "2.0"
      assert map.id == 1
      assert map.method == "initialize"
      assert map.params.clientInfo == request.client_info
      assert map.params.protocolVersion == request.protocol_version
      assert map.params.capabilities == request.capabilities
    end
    
    test "creates struct from map" do
      map = %{
        jsonrpc: "2.0",
        id: 2,
        method: "initialize",
        params: %{
          clientInfo: %{name: "TestClient", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{sampling: %{}}
        }
      }
      
      {:ok, request} = Types.from_map(map)
      
      assert %InitializeRequest{} = request
      assert request.id == 2
      assert request.client_info == map.params.clientInfo
      assert request.protocol_version == map.params.protocolVersion
      assert request.capabilities == map.params.capabilities
    end
  end
  
  describe "InitializeResult" do
    test "creates valid initialize result from struct" do
      server_info = %{name: "TestServer", version: "1.0.0"}
      protocol_version = "2025-03-26"
      capabilities = %{resources: %{subscribe: true}, tools: %{}}
      
      result = %InitializeResult{
        id: 1,
        server_info: server_info,
        protocol_version: protocol_version,
        capabilities: capabilities
      }
      
      assert result.id == 1
      assert result.server_info == server_info
      assert result.protocol_version == protocol_version
      assert result.capabilities == capabilities
    end
    
    test "converts struct to map" do
      result = %InitializeResult{
        id: 1,
        server_info: %{name: "TestServer", version: "1.0.0"},
        protocol_version: "2025-03-26",
        capabilities: %{resources: %{subscribe: true}}
      }
      
      map = Types.to_map(result)
      
      assert is_map(map)
      assert map.jsonrpc == "2.0"
      assert map.id == 1
      assert map.result.serverInfo == result.server_info
      assert map.result.protocolVersion == result.protocol_version
      assert map.result.capabilities == result.capabilities
    end
    
    test "creates struct from map" do
      map = %{
        jsonrpc: "2.0",
        id: 2,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      {:ok, result} = Types.from_map(map)
      
      assert %InitializeResult{} = result
      assert result.id == 2
      assert result.server_info == map.result.serverInfo
      assert result.protocol_version == map.result.protocolVersion
      assert result.capabilities == map.result.capabilities
    end
  end
  
  describe "InitializedNotification" do
    test "creates valid initialized notification from struct" do
      notification = %InitializedNotification{}
      
      assert notification != nil
    end
    
    test "converts struct to map" do
      notification = %InitializedNotification{}
      
      map = Types.to_map(notification)
      
      assert is_map(map)
      assert map.jsonrpc == "2.0"
      assert map.method == "notifications/initialized"
      assert map.params == %{}
      refute Map.has_key?(map, :id)
    end
    
    test "creates struct from map" do
      map = %{
        jsonrpc: "2.0",
        method: "notifications/initialized",
        params: %{}
      }
      
      {:ok, notification} = Types.from_map(map)
      
      assert %InitializedNotification{} = notification
    end
  end
  
  describe "ReadResourceRequest" do
    test "creates valid read resource request from struct" do
      request = %ReadResourceRequest{
        id: 3,
        uri: "file:///test.txt"
      }
      
      assert request.id == 3
      assert request.uri == "file:///test.txt"
    end
    
    test "converts struct to map" do
      request = %ReadResourceRequest{
        id: 3,
        uri: "file:///test.txt",
        range: %{start: 0, end: 100}
      }
      
      map = Types.to_map(request)
      
      assert is_map(map)
      assert map.jsonrpc == "2.0"
      assert map.id == 3
      assert map.method == "resources/read"
      assert map.params.uri == request.uri
      assert map.params.range == request.range
    end
    
    test "creates struct from map" do
      map = %{
        jsonrpc: "2.0",
        id: 3,
        method: "resources/read",
        params: %{
          uri: "file:///test.txt",
          range: %{start: 0, end: 100}
        }
      }
      
      {:ok, request} = Types.from_map(map)
      
      assert %ReadResourceRequest{} = request
      assert request.id == 3
      assert request.uri == map.params.uri
      assert request.range == map.params.range
    end
  end
  
  describe "ResourceContent" do
    test "creates a text resource content" do
      content = ResourceContent.text("Hello, world!")
      
      assert content.type == "text"
      assert content.text == "Hello, world!"
      refute Map.has_key?(content, :data)
    end
    
    test "creates an image resource content" do
      content = ResourceContent.image("base64data", "image/png")
      
      assert content.type == "image"
      assert content.data == "base64data"
      assert content.mime_type == "image/png"
      refute Map.has_key?(content, :text)
    end
    
    test "creates an audio resource content" do
      content = ResourceContent.audio("base64data", "audio/mp3")
      
      assert content.type == "audio"
      assert content.data == "base64data"
      assert content.mime_type == "audio/mp3"
      refute Map.has_key?(content, :text)
    end
    
    test "creates a resource reference" do
      content = ResourceContent.resource("file:///resource.txt")
      
      assert content.type == "resource"
      assert content.resource == "file:///resource.txt"
      refute Map.has_key?(content, :text)
    end
  end
  
  describe "detect_message_type/1" do
    test "detects initialize request" do
      map = %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{}
      }
      
      {:ok, type} = Types.detect_message_type(map)
      assert type == InitializeRequest
    end
    
    test "detects initialize result" do
      map = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{},
          protocolVersion: "2025-03-26"
        }
      }
      
      {:ok, type} = Types.detect_message_type(map)
      assert type == InitializeResult
    end
    
    test "detects initialized notification" do
      map = %{
        jsonrpc: "2.0",
        method: "notifications/initialized",
        params: %{}
      }
      
      {:ok, type} = Types.detect_message_type(map)
      assert type == InitializedNotification
    end
    
    test "returns error for unknown message type" do
      map = %{
        jsonrpc: "2.0",
        method: "unknown/method",
        params: %{}
      }
      
      assert {:error, _} = Types.detect_message_type(map)
    end
  end
end