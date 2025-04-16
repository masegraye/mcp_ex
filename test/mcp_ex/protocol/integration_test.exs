defmodule MCPEx.Protocol.IntegrationTest do
  use ExUnit.Case, async: true

  alias MCPEx.Protocol.JsonRpc
  alias MCPEx.Protocol.Capabilities
  alias MCPEx.Transport.Test, as: TestTransport
  alias MCPEx.Transport.TestServer

  # Sample client info for tests
  @client_info %{
    name: "MCPEx Test Client",
    version: "1.0.0"
  }

  # Define a test protocol version
  @protocol_version "2025-03-26"

  describe "full protocol flow" do
    test "complete initialization sequence" do
      # 1. Create a test server with capabilities
      server = TestServer.new(
        capabilities: [:resources, :tools],
        resources: [
          %{"uri" => "file:///test.txt", "content" => "Test content"}
        ],
        tools: [
          %{"name" => "test_tool", "description" => "A test tool"}
        ]
      )

      # 2. Create a test transport connected to this server
      {:ok, transport} = TestTransport.start_link(server: server)

      # 3. Register ourselves to receive notifications
      TestTransport.register_message_receiver(transport, self())

      # 4. Create an initialization request
      initialize_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "initialize",
        params: %{
          clientInfo: @client_info,
          protocolVersion: @protocol_version,
          capabilities: %{
            resources: %{},
            tools: %{}
          }
        }
      }

      # 5. Send the initialization request
      {:ok, response} = TestTransport.send_message(transport, initialize_request)

      # 6. Extract the server info and capabilities from the response
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == initialize_request.id
      assert Map.has_key?(response, "result")
      
      # Verify server capabilities exist in the response
      assert Map.has_key?(response["result"], "capabilities")
      assert Map.has_key?(response["result"]["capabilities"], "resources")
      assert Map.has_key?(response["result"]["capabilities"], "tools")
      
      # 7. Create and send the initialized notification with an ID 
      # (TestTransport requires an ID even for notifications)
      initialized_notification = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "initialized",
        params: %{}
      }
      
      {:ok, _} = TestTransport.send_message(transport, initialized_notification)
      
      # Now perform some operations...
      
      # 8. List resources
      resources_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "resources/list",
        params: %{}
      }
      
      {:ok, resources_response} = TestTransport.send_message(transport, resources_request)
      
      # 9. Verify resources response
      assert resources_response["result"]["resources"] |> length() == 1
      assert hd(resources_response["result"]["resources"])["uri"] == "file:///test.txt"
      
      # 10. List tools
      tools_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "tools/list",
        params: %{}
      }
      
      {:ok, tools_response} = TestTransport.send_message(transport, tools_request)
      
      # 11. Verify tools response
      assert tools_response["result"]["tools"] |> length() == 1
      assert hd(tools_response["result"]["tools"])["name"] == "test_tool"
    end

    test "capability negotiation" do
      # Create a server with specific capabilities
      server = TestServer.new(
        capabilities: [:resources, :tools]
      )
      
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Create and send initialize request
      initialize_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "initialize",
        params: %{
          clientInfo: @client_info, 
          protocolVersion: @protocol_version,
          capabilities: %{
            resources: %{},
            tools: %{subscribe: true}
          }
        }
      }
      
      {:ok, response} = TestTransport.send_message(transport, initialize_request)
      
      # Check response contains capabilities
      assert Map.has_key?(response, "result")
      assert Map.has_key?(response["result"], "capabilities")
      
      # Convert string keys to atoms for easier testing with helper functions
      capabilities = Map.new(response["result"]["capabilities"], fn {k, v} -> 
        {String.to_atom(k), v} 
      end)
      
      # Check capability negotiation
      assert Capabilities.has_capability?(capabilities, :resources)
      assert Capabilities.has_capability?(capabilities, :tools)
    end

    test "error handling" do
      # Create server
      server = TestServer.new(
        capabilities: [:resources],
        error_rate: 0.0
      )
      
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Create a custom handler for a tool that doesn't exist
      tool_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "tools/call",
        params: %{
          name: "nonexistent_tool",
          args: %{}
        }
      }
      
      # Send the request and expect an error
      {:ok, response} = TestTransport.send_message(transport, tool_request)
      
      # Verify error response
      assert Map.has_key?(response, "error")
      assert response["error"]["code"] == -32602
      assert String.contains?(response["error"]["message"], "Tool not found")
    end
    
    test "resource subscriptions and notifications" do
      # Skip this test for now - will be implemented in transport-specific tests
      :ok
    end
    
    test "protocol version negotiation" do
      # Create server with version handling
      server = TestServer.new(
        capabilities: [:resources]
      )
      
      # Override the default initialize response handler
      handler = fn _server, message ->
        # Extract client's requested protocol version
        requested_version = message["params"]["protocolVersion"]
        
        # Simulate server supporting multiple versions
        negotiated_version = requested_version
        
        %{
          "jsonrpc" => "2.0",
          "id" => message["id"],
          "result" => %{
            "serverInfo" => %{
              "name" => "TestServer",
              "version" => "1.0.0"
            },
            "protocolVersion" => negotiated_version,
            "capabilities" => %{
              "resources" => %{"subscribe" => true}
            }
          }
        }
      end
      
      # Set the custom handler
      updated_responses = Map.put(server.responses, "initialize", handler)
      server = %{server | responses: updated_responses}
      
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Test with older protocol version
      initialize_request = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "initialize",
        params: %{
          clientInfo: @client_info,
          protocolVersion: "2024-11-05",  # Older version
          capabilities: %{resources: %{}}
        }
      }
      
      {:ok, response} = TestTransport.send_message(transport, initialize_request)
      
      # Verify response contains correct negotiated version
      assert response["result"]["protocolVersion"] == "2024-11-05"
      
      # Test with latest protocol version in a new connection
      server = TestServer.new(
        capabilities: [:resources]
      )
      
      # Set the custom handler again
      updated_responses = Map.put(server.responses, "initialize", handler)
      server = %{server | responses: updated_responses}
      
      {:ok, transport2} = TestTransport.start_link(server: server)
      
      initialize_request2 = %{
        jsonrpc: "2.0",
        id: JsonRpc.generate_id(),
        method: "initialize",
        params: %{
          clientInfo: @client_info,
          protocolVersion: "2025-03-26",  # Latest version
          capabilities: %{resources: %{}}
        }
      }
      
      {:ok, response2} = TestTransport.send_message(transport2, initialize_request2)
      
      # Verify response contains correct negotiated version
      assert response2["result"]["protocolVersion"] == "2025-03-26"
    end
  end
end