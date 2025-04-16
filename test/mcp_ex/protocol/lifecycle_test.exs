defmodule MCPEx.Protocol.LifecycleTest do
  use ExUnit.Case, async: true
  
  alias MCPEx.Protocol.Lifecycle
  alias MCPEx.Protocol.Types.{InitializeRequest, InitializedNotification}
  
  describe "create_initialize_request/3" do
    test "creates valid initialize request" do
      client_info = %{name: "TestClient", version: "1.0.0"}
      protocol_version = "2025-03-26"
      capabilities = %{sampling: %{}, roots: %{listChanged: true}}
      
      request = Lifecycle.create_initialize_request(client_info, capabilities, protocol_version)
      
      assert %InitializeRequest{} = request
      assert request.client_info == client_info
      assert request.protocol_version == protocol_version
      assert request.capabilities == capabilities
      assert is_integer(request.id)
    end
    
    test "uses default protocol version when not specified" do
      client_info = %{name: "TestClient", version: "1.0.0"}
      capabilities = %{sampling: %{}}
      
      request = Lifecycle.create_initialize_request(client_info, capabilities)
      
      assert request.protocol_version == "2025-03-26"
    end
  end
  
  describe "create_initialized_notification/0" do
    test "creates valid initialized notification" do
      notification = Lifecycle.create_initialized_notification()
      
      assert %InitializedNotification{} = notification
    end
  end
  
  describe "process_initialize_response/1" do
    test "processes valid initialize response" do
      response = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert {:ok, result} = Lifecycle.process_initialize_response(response)
      assert result.server_info == response.result.serverInfo
      assert result.protocol_version == response.result.protocolVersion
      assert result.capabilities == response.result.capabilities
    end
    
    test "returns error for invalid response" do
      # Missing protocolVersion
      response = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert {:error, _reason} = Lifecycle.process_initialize_response(response)
    end
    
    test "returns error for error response" do
      response = %{
        jsonrpc: "2.0",
        id: 1,
        error: %{
          code: -32600,
          message: "Invalid Request"
        }
      }
      
      assert {:error, _reason} = Lifecycle.process_initialize_response(response)
    end
  end
  
  describe "process_server_capabilities/1" do
    test "processes valid capabilities" do
      capabilities = %{
        resources: %{subscribe: true, listChanged: true},
        tools: %{listChanged: false},
        prompts: %{}
      }
      
      {:ok, processed} = Lifecycle.process_server_capabilities(capabilities)
      
      assert processed.resources.subscribe
      assert processed.resources.listChanged
      refute Map.get(processed.tools, :listChanged, false)
      assert Map.has_key?(processed, :prompts)
    end
    
    test "handles nil or non-map capabilities gracefully" do
      assert {:error, _} = Lifecycle.process_server_capabilities(nil)
      assert {:error, _} = Lifecycle.process_server_capabilities("invalid")
    end
  end
  
  describe "validate_server_initialization/1" do
    test "validates valid response" do
      response = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          protocolVersion: "2025-03-26",
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert :ok = Lifecycle.validate_server_initialization(response)
    end
    
    test "returns error for incompatible protocol version" do
      response = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          serverInfo: %{name: "TestServer", version: "1.0.0"},
          protocolVersion: "1.0.0", # Incompatible version
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert {:error, _reason} = Lifecycle.validate_server_initialization(response)
    end
    
    test "returns error for missing required fields" do
      # Missing serverInfo
      response = %{
        jsonrpc: "2.0",
        id: 1,
        result: %{
          protocolVersion: "2025-03-26",
          capabilities: %{resources: %{subscribe: true}}
        }
      }
      
      assert {:error, _reason} = Lifecycle.validate_server_initialization(response)
    end
  end
  
  describe "check_required_capabilities/2" do
    test "passes when all required capabilities are present" do
      server_capabilities = %{
        resources: %{subscribe: true},
        tools: %{},
        prompts: %{}
      }
      
      required_capabilities = [:resources, :tools]
      
      assert :ok = Lifecycle.check_required_capabilities(server_capabilities, required_capabilities)
    end
    
    test "returns error when required capabilities are missing" do
      server_capabilities = %{
        resources: %{subscribe: true},
        tools: %{}
      }
      
      required_capabilities = [:resources, :tools, :prompts]
      
      assert {:error, _reason} = Lifecycle.check_required_capabilities(server_capabilities, required_capabilities)
    end
    
    test "checks for sub-capabilities when specified" do
      server_capabilities = %{
        resources: %{subscribe: true}
      }
      
      required_capabilities = [resources: [:subscribe]]
      
      assert :ok = Lifecycle.check_required_capabilities(server_capabilities, required_capabilities)
      
      # Test with missing sub-capability
      required_capabilities = [resources: [:subscribe, :listChanged]]
      
      assert {:error, _reason} = Lifecycle.check_required_capabilities(server_capabilities, required_capabilities)
    end
  end
end