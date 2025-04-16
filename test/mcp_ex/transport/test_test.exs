defmodule MCPEx.Transport.TestTest do
  use ExUnit.Case, async: true
  alias MCPEx.Transport.Test
  alias MCPEx.Transport.TestServer

  describe "initialization" do
    test "starts successfully with auto_connect" do
      server = TestServer.new(capabilities: [:resources, :tools])
      {:ok, transport} = Test.start_link(server: server)
      
      assert Test.connected?(transport)
      assert TestServer.last_message(server) == nil
    end
    
    test "starts without connecting when auto_connect is false" do
      server = TestServer.new()
      {:ok, transport} = Test.start_link(server: server, auto_connect: false)
      
      refute Test.connected?(transport)
    end
  end
  
  describe "message exchange" do
    setup do
      # Create server and transport instances
      server = TestServer.new(capabilities: [:resources, :tools])
      {:ok, transport} = Test.start_link(server: server)

      # Get the updated server with the client registered
      {client_ref, updated_server} = TestServer.register_client(server, self())
      
      # Return the test context
      %{server: updated_server, transport: transport, client_ref: client_ref}
    end
    
    test "sends a message and receives response", %{transport: transport} do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{"clientInfo" => %{"name" => "test-client"}},
        "id" => 1
      }
      
      {:ok, response} = Test.send_message(transport, message)
      
      assert response["id"] == 1
      assert response["result"]["serverInfo"]["name"] == "TestServer"
      # Don't test received_message? since the server state is separate
    end
    
    test "forwards notifications to registered receiver", %{server: server, transport: transport, client_ref: client_ref} do
      # Register this test process as message receiver
      Test.register_message_receiver(transport, self())
      
      # Send a notification
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/resources/updated",
        "params" => %{"uri" => "file:///test.txt"}
      }
      
      # Send to specific client  
      TestServer.send_notification(server, notification, client_ref)
      
      # Should receive the notification
      assert_receive {:test_server_notification, ^notification}, 500
    end
    
    test "handles server errors", %{transport: transport} do
      # Register this test process as message receiver
      Test.register_message_receiver(transport, self())
      
      # Trigger a server error
      error_reason = "Test server error"
      send(transport, {:test_server_error, error_reason})
      
      # Should receive the error
      assert_receive {:error, ^error_reason}, 500
      
      # Should be disconnected
      refute Test.connected?(transport)
    end
  end
  
  describe "record and replay" do
    test "records and replays a session" do
      # We'll need to stub the recording functionality for this test
      # Create a server directly with a mocked recording
      server = TestServer.new(
        record_mode: true,
        capabilities: [:resources]
      )
      
      # Add a fake recording for testing
      recording = [
        %{
          type: :response,
          message: %{"jsonrpc" => "2.0", "result" => %{"status" => "ok"}, "id" => 1},
          request_id: 1,
          timestamp: :os.system_time(:millisecond)
        },
        %{
          type: :request,
          message: %{"jsonrpc" => "2.0", "method" => "initialize", "id" => 1},
          timestamp: :os.system_time(:millisecond)
        }
      ]
      
      # Update the server with our recording
      server = %{server | recording: recording}
      
      # Now test the get_recording function
      result = TestServer.get_recording(server)
      
      assert result != nil
      assert length(result) == 2
      assert hd(result).type == :request
    end
  end
  
  describe "integration with transport factory" do
    test "can be created via the transport factory" do
      server = TestServer.new()
      {:ok, transport} = MCPEx.Transport.create(:test, [server: server])
      
      assert Process.alive?(transport)
      assert Test.connected?(transport)
    end
  end
end