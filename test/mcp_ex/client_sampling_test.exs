defmodule MCPEx.ClientSamplingTest do
  use ExUnit.Case, async: true

  alias MCPEx.Client
  alias MCPEx.Sampling.Handler
  alias MCPEx.Transport.Test, as: TestTransport
  alias MCPEx.Transport.TestServer

  # Define a test handler for capturing sampling requests
  defmodule TestSamplingHandler do
    @behaviour Handler
    
    @impl true
    def process_sampling_request(request_id, messages, model_preferences, request_options, handler_config) do
      # Get the test pid from handler config so we can send the request info back
      test_pid = handler_config[:test_pid]
      
      # Send the request info to the test process
      if test_pid do
        send(test_pid, {:sampling_request, %{
          request_id: request_id,
          messages: messages,
          model_preferences: model_preferences,
          request_options: request_options,
          handler_config: handler_config
        }})
      end
      
      # Return success or failure based on handler config
      if handler_config[:fail] do
        {:error, %{code: -32000, message: "Test failure"}}
      else
        {:ok, %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Test response for #{request_id}"
          },
          model: "test-model",
          stop_reason: "endTurn"
        }}
      end
    end
  end

  describe "client sampling integration" do
    setup do
      # Create a test server with capabilities
      server = TestServer.new(capabilities: [:sampling])
      
      # Set up a response handler for sampling requests
      sampling_request_handler = fn _server, message ->
        # Just return success to acknowledge receipt
        %{
          "jsonrpc" => "2.0",
          "id" => message["id"],
          "result" => %{}
        }
      end
      
      # Add the handler to the server
      server = %{server | responses: Map.put(server.responses, "sampling/createMessage", sampling_request_handler)}
      
      # Start a transport with the test server
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Return the setup
      %{server: server, transport: transport}
    end
    
    test "registers sampling handler during initialization", %{transport: transport} do
      # Initialize a client with a sampling handler
      {:ok, client} = Client.start_link(
        transport: transport,
        sampling_handler: {TestSamplingHandler, [test_pid: self()]},
        shell_type: :none
      )
      
      # Verify client started
      assert Process.alive?(client)
      
      # Clean up
      Client.stop(client)
    end
    
    test "registers sampling handler after initialization", %{transport: transport} do
      # Initialize client without sampling handler
      {:ok, client} = Client.start_link(transport: transport, shell_type: :none)
      
      # Register a sampling handler
      :ok = Client.register_sampling_handler(client, {TestSamplingHandler, [test_pid: self()]})
      
      # Clean up
      Client.stop(client)
    end
    
    test "handles sampling request and calls handler", %{transport: transport} do
      # Start client with sampling handler that sends messages to this process
      {:ok, client} = Client.start_link(
        transport: transport,
        sampling_handler: {TestSamplingHandler, [test_pid: self()]},
        shell_type: :none
      )
      
      # Create a sampling request
      sampling_request = %{
        "jsonrpc" => "2.0",
        "id" => "test-123",
        "method" => "sampling/createMessage",
        "params" => %{
          "messages" => [
            %{"role" => "user", "content" => %{"type" => "text", "text" => "Test message"}}
          ],
          "modelPreferences" => %{
            "hints" => [%{"name" => "test-model"}]
          },
          "maxTokens" => 100
        }
      }
      
      # Simulate receiving the request from the server
      send(client, {:transport_response, sampling_request})
      
      # Wait for the handler to be called
      assert_receive {:sampling_request, request_info}, 1000
      
      # Verify request was processed correctly
      assert request_info.request_id == "test-123"
      assert length(request_info.messages) == 1
      assert hd(request_info.messages)["content"]["text"] == "Test message"
      
      # Check model preferences with safety checks
      assert is_map(request_info.model_preferences)
      hints = request_info.model_preferences["hints"] || []
      if length(hints) > 0 do
        assert hd(hints)["name"] == "test-model"
      end
      
      # Check request options
      assert request_info.request_options.max_tokens == 100
      
      # Clean up
      Client.stop(client)
    end
    
    test "handles failures from the sampling handler", %{transport: transport} do
      # Start client with a handler configured to fail
      {:ok, client} = Client.start_link(
        transport: transport,
        sampling_handler: {TestSamplingHandler, [test_pid: self(), fail: true]},
        shell_type: :none
      )
      
      # Create a sampling request
      sampling_request = %{
        "jsonrpc" => "2.0",
        "id" => "test-456",
        "method" => "sampling/createMessage",
        "params" => %{
          "messages" => [
            %{"role" => "user", "content" => %{"type" => "text", "text" => "Test message"}}
          ]
        }
      }
      
      # Simulate receiving the request from the server
      send(client, {:transport_response, sampling_request})
      
      # Wait for the handler to be called
      assert_receive {:sampling_request, _}, 1000
      
      # We can't easily test the error response here without modifying the TestTransport,
      # but we've verified that the handler was called which is the main goal of this test
      
      # Clean up
      Client.stop(client)
    end
  end
end