defmodule MCPEx.Transport.TestServerTest do
  use ExUnit.Case, async: true
  alias MCPEx.Transport.TestServer

  describe "initialization" do
    test "creates a new server with default options" do
      server = TestServer.new()
      
      assert server.clients == []
      assert server.capabilities == []
      assert server.resources == []
      assert server.tools == []
      assert server.prompts == []
      assert server.scenario == nil
      assert server.delay == 0
      assert server.error_rate == 0.0
    end
    
    test "creates a new server with custom options" do
      server = TestServer.new(
        capabilities: [:resources, :tools],
        scenario: :resource_changes,
        delay: 100,
        error_rate: 0.2,
        resources: [%{"uri" => "file:///test.txt"}],
        tools: [%{"name" => "test-tool"}],
        prompts: [%{"name" => "test-prompt"}]
      )
      
      assert server.capabilities == [:resources, :tools]
      assert server.scenario == :resource_changes
      assert server.delay == 100
      assert server.error_rate == 0.2
      assert length(server.resources) == 1
      assert length(server.tools) == 1
      assert length(server.prompts) == 1
    end
  end
  
  describe "client management" do
    test "registers and unregisters clients" do
      server = TestServer.new()
      pid = self()
      
      {client_ref, updated_server} = TestServer.register_client(server, pid)
      assert is_reference(client_ref)
      assert length(updated_server.clients) == 1
      assert Enum.any?(updated_server.clients, fn {ref, client_pid} -> 
        ref == client_ref && client_pid == pid
      end)
      
      final_server = TestServer.unregister_client(updated_server, client_ref)
      assert final_server.clients == []
    end
  end
  
  describe "message processing" do
    setup do
      server = TestServer.new(capabilities: [:resources, :tools])
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      %{server: server, client_ref: client_ref}
    end
    
    test "processes initialize message", %{server: server, client_ref: client_ref} do
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{"clientInfo" => %{"name" => "test-client"}},
        "id" => 1
      })
      
      {response, updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["id"] == 1
      assert response["result"]["serverInfo"]["name"] == "TestServer"
      assert length(updated_server.received_messages) == 1
    end
    
    test "processes resources/list message", %{server: server, client_ref: client_ref} do
      # Add a resource first
      server = TestServer.add_resource(server, %{"uri" => "file:///test.txt", "content" => "Hello"})
      
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "resources/list",
        "id" => 2
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["id"] == 2
      assert length(response["result"]["resources"]) == 1
      assert hd(response["result"]["resources"])["uri"] == "file:///test.txt"
    end
    
    test "processes tools/list message", %{server: server, client_ref: client_ref} do
      # Add a tool first
      server = TestServer.add_tool(server, %{"name" => "test-tool", "description" => "A test tool"})
      
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => 3
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["id"] == 3
      assert length(response["result"]["tools"]) == 1
      assert hd(response["result"]["tools"])["name"] == "test-tool"
    end
    
    test "processes tools/call message", %{server: server, client_ref: client_ref} do
      # Add a tool with a handler
      tool = %{
        "name" => "calculator",
        "description" => "Adds two numbers",
        "handler" => fn args -> args["a"] + args["b"] end
      }
      server = TestServer.add_tool(server, tool)
      
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "params" => %{
          "name" => "calculator",
          "args" => %{"a" => 40, "b" => 2}
        },
        "id" => 4
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["id"] == 4
      assert response["result"]["is_error"] == false
      # Result will be a string since the handler result is converted via inspect
      assert Enum.at(response["result"]["content"], 0)["text"] == "42"
    end
    
    test "handles unknown method", %{server: server, client_ref: client_ref} do
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "unknown_method",
        "id" => 5
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["id"] == 5
      assert response["error"]["code"] == -32601
      assert String.contains?(response["error"]["message"], "Method not found")
    end
    
    test "handles parse error", %{server: server, client_ref: client_ref} do
      {response, _updated_server} = TestServer.process_message(server, client_ref, "invalid json")
      
      assert response["error"]["code"] == -32700
      assert String.contains?(response["error"]["message"], "Parse error")
    end
  end
  
  describe "notifications" do
    setup do
      server = TestServer.new()
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      %{server: server, client_ref: client_ref}
    end
    
    test "sends notification to specific client", %{server: server, client_ref: client_ref} do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/test",
        "params" => %{"value" => "test"}
      }
      
      # The test process is registered as a client, so it should receive the notification
      TestServer.send_notification(server, notification, client_ref)
      
      assert_receive {:test_server_notification, ^notification}, 500
    end
    
    test "sends notification to all clients", %{server: server} do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/broadcast",
        "params" => %{"value" => "broadcast"}
      }
      
      # The test process is registered as a client, so it should receive the notification
      TestServer.send_notification(server, notification)
      
      assert_receive {:test_server_notification, ^notification}, 500
    end
  end
  
  describe "resources management" do
    test "adds a resource and notifies clients" do
      server = TestServer.new()
      pid = self()
      {_client_ref, server} = TestServer.register_client(server, pid)
      
      resource = %{"uri" => "file:///test.txt", "content" => "Hello, world!"}
      updated_server = TestServer.add_resource(server, resource)
      
      assert length(updated_server.resources) == 1
      assert hd(updated_server.resources)["uri"] == "file:///test.txt"
      
      # Should receive a notification about the resource change
      assert_receive {:test_server_notification, notification}, 500
      assert notification["method"] == "notifications/resources/list_changed"
    end
  end
  
  describe "tools management" do
    test "adds a tool and notifies clients" do
      server = TestServer.new()
      pid = self()
      {_client_ref, server} = TestServer.register_client(server, pid)
      
      tool = %{"name" => "test-tool", "description" => "A test tool"}
      updated_server = TestServer.add_tool(server, tool)
      
      assert length(updated_server.tools) == 1
      assert hd(updated_server.tools)["name"] == "test-tool"
      
      # Should receive a notification about the tool change
      assert_receive {:test_server_notification, notification}, 500
      assert notification["method"] == "notifications/tools/list_changed"
    end
  end
  
  describe "prompts management" do
    test "adds a prompt and notifies clients" do
      server = TestServer.new()
      pid = self()
      {_client_ref, server} = TestServer.register_client(server, pid)
      
      prompt = %{"name" => "test-prompt", "description" => "A test prompt"}
      updated_server = TestServer.add_prompt(server, prompt)
      
      assert length(updated_server.prompts) == 1
      assert hd(updated_server.prompts)["name"] == "test-prompt"
      
      # Should receive a notification about the prompt change
      assert_receive {:test_server_notification, notification}, 500
      assert notification["method"] == "notifications/prompts/list_changed"
    end
  end
  
  describe "scenarios" do
    test "resource changes scenario triggers events" do
      server = TestServer.new(scenario: :resource_changes)
      pid = self()
      
      # Registering a client should trigger the scenario
      {_client_ref, _server} = TestServer.register_client(server, pid)
      
      # First, we should get a resource addition
      assert_receive {:test_server_notification, notification1}, 500
      assert notification1["method"] == "notifications/resources/list_changed"
      
      # Then, we should get a resource update
      assert_receive {:test_server_notification, notification2}, 500
      assert notification2["method"] == "notifications/resources/updated"
      assert notification2["params"]["uri"] == "file:///test.txt"
    end
    
    test "connection error scenario triggers error" do
      server = TestServer.new(scenario: :connection_error)
      pid = self()
      
      # Registering a client should trigger the scenario
      {_client_ref, _server} = TestServer.register_client(server, pid)
      
      # Should receive an error after a short delay
      assert_receive {:test_server_error, "Simulated connection error"}, 500
    end
  end
  
  describe "error simulation" do
    test "simulates errors based on error_rate" do
      # Set a 100% error rate to guarantee errors
      server = TestServer.new(error_rate: 1.0)
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["error"]["code"] == -32000
      assert response["error"]["message"] == "Simulated error"
    end
  end
  
  describe "query functions" do
    test "received_message? checks for messages" do
      server = TestServer.new()
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1
      })
      
      {_response, updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert TestServer.received_message?(updated_server, method: "initialize")
      refute TestServer.received_message?(updated_server, method: "unknown")
      assert TestServer.received_message?(updated_server, id: 1)
      refute TestServer.received_message?(updated_server, id: 999)
    end
    
    test "last_message returns the most recent message" do
      server = TestServer.new()
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      # Send two messages
      message1 = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1
      })
      
      {_response1, server1} = TestServer.process_message(server, client_ref, message1)
      
      message2 = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "resources/list",
        "id" => 2
      })
      
      {_response2, server2} = TestServer.process_message(server1, client_ref, message2)
      
      # Last message should be the resources/list one
      last = TestServer.last_message(server2)
      assert last["method"] == "resources/list"
      assert last["id"] == 2
      
      # All messages should include both
      all = TestServer.received_messages(server2)
      assert length(all) == 2
    end
  end
  
  describe "custom response handlers" do
    test "sets a custom response handler for a method" do
      server = TestServer.new()
      pid = self()
      {client_ref, server} = TestServer.register_client(server, pid)
      
      # Set a custom handler for the ping method
      custom_handler = fn _server, message -> 
        %{
          "jsonrpc" => "2.0",
          "result" => "pong",
          "id" => message["id"]
        }
      end
      
      server = TestServer.set_response_handler(server, "ping", custom_handler)
      
      # Send a ping message
      message = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "ping",
        "id" => 1
      })
      
      {response, _updated_server} = TestServer.process_message(server, client_ref, message)
      
      assert response["result"] == "pong"
      assert response["id"] == 1
    end
  end
end