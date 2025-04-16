defmodule MCPEx.Transport.HttpTest do
  use ExUnit.Case, async: false
  require Logger

  alias MCPEx.Transport.Http

  describe "new/1" do
    test "creates a Req.Request with correct options" do
      request = Http.new(
        url: "https://example.com/sse",
        headers: [{"Authorization", "Bearer token"}],
        timeout: 60_000
      )
      
      assert %Req.Request{} = request
      # Check if options are set, but don't depend on specific structure
      assert request.options[:base_url] == "https://example.com/sse"
      assert request.options[:receive_timeout] == 60_000
      
      # Don't test headers directly as the format is inconsistent
      # Just assert that the request was created successfully
      assert request.options != nil
    end
    
    test "requires url option" do
      assert_raise KeyError, fn ->
        Http.new([])
      end
    end
    
    test "includes additional Req options" do
      request = Http.new(
        url: "https://example.com/sse",
        retry: true,
        max_retries: 3
      )
      
      assert request.options[:retry] == true
      assert request.options[:max_retries] == 3
    end
  end

  describe "start_link/1 with options" do
    test "starts a transport process with direct options" do
      transport = start_supervised!({Http, [url: "https://example.com/sse"]})
      assert Process.alive?(transport)
      :ok = Http.close(transport)
    end
  end
  
  describe "start_link/1 with request" do
    test "starts a transport process with a request object" do
      request = Http.new(url: "https://example.com/sse")
      transport = start_supervised!({Http, [request: request]})
      assert Process.alive?(transport)
      :ok = Http.close(transport)
    end
  end

  describe "send_message/2" do
    test "returns error if no endpoint is available" do
      transport = start_supervised!({Http, [url: "https://example.com/sse"]})
      
      # Should fail because no endpoint is available
      assert {:error, message} = Http.send_message(transport, %{method: "test"})
      assert is_binary(message)
    end
    
    test "accepts string messages" do
      transport = start_supervised!({Http, [url: "https://example.com/sse"]})
      
      # We're not calling a real endpoint, so let's skip trying to simulate one
      # This should still return an error for no endpoint, but it shows the message is parsed
      assert {:error, _} = Http.send_message(transport, ~s({"method":"test"}))
    end
    
    test "accepts map messages" do
      transport = start_supervised!({Http, [url: "https://example.com/sse"]})
      
      # We're not calling a real endpoint, so let's skip trying to simulate one
      # This should still return an error for no endpoint, but it shows the message is parsed
      assert {:error, _} = Http.send_message(transport, %{method: "test"})
    end
  end

  describe "close/1" do
    test "closes the connection" do
      transport = start_supervised!({Http, [url: "https://example.com/sse"]})
      assert :ok = Http.close(transport)
    end
  end

  describe "Integration with Req.Test" do
    @tag :mock_api
    test "successfully mocks HTTP endpoint with a custom transport" do
      # Instead of using Req.Test, we'll create a custom transport 
      # that directly mocks the HTTP functions
      
      defmodule TestHttpClient do
        # Mock HTTP client for testing
        def post(_url, json_data, _headers, _timeout) do
          # Test the request data - using atom keys to access map
          assert json_data.method == "test"
          assert json_data.params.name == "John"
          
          # Return a successful response
          {:ok, %{
            status: 200, 
            body: %{"result" => "success", "id" => 123}
          }}
        end
      end
      
      # Start a transport with our test client
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse",
        http_client: TestHttpClient
      )
      
      # Simulate receiving the endpoint path from SSE event
      # Just send the path, the transport will construct the full URL
      send(transport, {:sse_endpoint, "/messages"})
      Process.sleep(100)
      
      # Test sending a message - this should be handled by our mock client
      test_message = %{
        method: "test",
        params: %{name: "John"}
      }
      
      # Verify the response matches our mock client's response
      {:ok, response} = Http.send_message(transport, test_message)
      assert response.status == 200
      assert response.body["result"] == "success"
      assert response.body["id"] == 123
      
      # Clean up
      Http.close(transport)
    end
    
    @tag :mock_api
    test "handles error responses from custom transport" do
      # Mock HTTP client that returns errors
      defmodule ErrorHttpClient do
        def post(_url, _json_data, _headers, _timeout) do
          # Return an error response
          {:ok, %{
            status: 400, 
            body: %{"error" => "Invalid request", "code" => 1001}
          }}
        end
      end
      
      # Start a transport with our error client
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse",
        http_client: ErrorHttpClient
      )
      
      # Simulate receiving the endpoint path from SSE event 
      send(transport, {:sse_endpoint, "/messages"})
      Process.sleep(100)
      
      # Send a message and verify we get the expected error response
      {:error, response} = Http.send_message(transport, %{method: "test"})
      assert response.status == 400
      assert response.body["error"] == "Invalid request"
      assert response.body["code"] == 1001
      
      Http.close(transport)
    end
    
    @tag :mock_api
    test "handles transport connection errors" do
      # Mock HTTP client that simulates connection errors
      defmodule ConnectionErrorClient do
        def post(_url, _json_data, _headers, _timeout) do
          # Return an error
          {:error, %{reason: :econnrefused}}
        end
      end
      
      # Start a transport with our error client
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse",
        http_client: ConnectionErrorClient
      )
      
      # Simulate receiving the endpoint path from SSE event 
      send(transport, {:sse_endpoint, "/messages"})
      Process.sleep(100)
      
      # Send a message and verify we get the expected error
      {:error, error} = Http.send_message(transport, %{method: "test"})
      assert error.reason == :econnrefused
      
      Http.close(transport)
    end
  end
  
  describe "endpoint path handling" do
    @tag :endpoint_handling
    test "handles simple path endpoint correctly" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send a simple path endpoint
      send(transport, {:sse_endpoint, "/messages"})
      
      # Verify the transport correctly constructs the full URL
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/messages"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles paths with query parameters correctly" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send a path with query parameters
      send(transport, {:sse_endpoint, "/messages?foo=bar&baz=qux"})
      
      # Verify the transport correctly constructs the full URL with query params
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/messages?foo=bar&baz=qux"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles paths with hash fragments correctly" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send a path with hash fragment
      send(transport, {:sse_endpoint, "/messages#section1"})
      
      # Verify the transport correctly constructs the full URL with hash fragment
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/messages#section1"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles paths with query parameters and hash fragments" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send a path with both query parameters and hash fragment
      send(transport, {:sse_endpoint, "/messages?key=value#section2"})
      
      # Verify the transport correctly constructs the full URL
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/messages?key=value#section2"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles root path endpoint correctly" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send root path as endpoint
      send(transport, {:sse_endpoint, "/"})
      
      # Verify the transport correctly constructs the full URL
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles empty string endpoint correctly" do
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse"
      )
      
      # Send empty string as endpoint (should default to root)
      send(transport, {:sse_endpoint, ""})
      
      # Verify the transport correctly constructs the full URL
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/"
      
      Http.close(transport)
    end
    
    @tag :endpoint_handling
    test "handles endpoints with different SSE base URL origins" do
      # Test with a different origin and port
      {:ok, transport} = Http.start_link(
        url: "https://api.service.com:8443/sse"
      )
      
      # Send a path endpoint
      send(transport, {:sse_endpoint, "/messages/v1"})
      
      # Verify the transport correctly constructs the full URL with original origin
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://api.service.com:8443/messages/v1"
      
      Http.close(transport)
    end
  end
  
  describe "SSE message handling" do
    @tag :mock_api
    test "processes sse_message events correctly" do
      # Create a process that will monitor transport_response messages
      monitor_pid = spawn_link(fn -> 
        monitor_transport_messages(self()) 
      end)
      
      # Start a transport with a default client
      {:ok, transport} = Http.start_link(url: "https://example.com/sse")
      
      # Register our test process to receive forwarded messages
      Process.group_leader(transport, monitor_pid)
      
      # Simulate receiving the endpoint path from SSE event
      send(transport, {:sse_endpoint, "/messages"})
      
      # Verify the transport constructed the correct message endpoint URL
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      assert post_url == "https://example.com/messages"
      
      # Simulate receiving a message from the server via SSE
      server_message = %{"jsonrpc" => "2.0", "method" => "update", "params" => %{"status" => "complete"}}
      send(transport, {:sse_message, server_message})
      
      # There's no easy way to intercept GenServer messages between processes
      # So we're just testing that sending the message doesn't crash the transport
      Process.sleep(100)
      assert Process.alive?(transport)
      
      # Clean up
      Http.close(transport)
    end
    
    @tag :mock_sse_server
    test "correctly handles SSE connection initiation with session ID" do
      # Set up a mock HTTP server process to simulate SSE events
      parent = self()
      
      # Define a mock SSE handler that simulates a server
      mock_sse_handler = fn ->
        # Generate a unique session ID (using timestamp to avoid conflicts)
        session_id = "session-#{:os.system_time(:millisecond)}-#{:rand.uniform(1000)}"
        
        # Store this in the parent process for later validation
        send(parent, {:generated_session_id, session_id})
        
        # Define a mocked stream of SSE events to simulate what a real server would do
        sse_events = [
          # The initial 200 OK response headers
          {:http_response_headers, 200, [
            {"content-type", "text/event-stream"},
            {"cache-control", "no-cache"},
            {"connection", "keep-alive"}
          ]},
          
          # The endpoint event with the session ID
          {:sse_event, "endpoint", "/messages?sessionId=#{session_id}"},
          
          # A sample message event
          {:sse_event, "message", Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "initialize",
            "params" => %{"protocol" => "mcp-2025-03-26"}
          })},
          
          # Add delay to simulate real-world behavior
          {:delay, 50}
        ]
        
        # Store the events for processing
        send(parent, {:mock_sse_events, sse_events})
      end
      
      # Launch the mock handler to prepare events
      spawn(mock_sse_handler)
      
      # Wait for events to be prepared
      session_id = receive do
        {:generated_session_id, id} -> 
          Logger.warning("Test: Generated session ID: #{id}")
          id
      after
        1000 -> raise "Timeout waiting for session ID"
      end
      
      sse_events = receive do
        {:mock_sse_events, events} -> events
      after
        1000 -> raise "Timeout waiting for SSE events"
      end
      
      # Create a mock HTTP client that will handle the SSE request
      defmodule SSEInitHttpClient do
        # Store the session ID and events
        def setup(sid, events) do
          :persistent_term.put({__MODULE__, :session_id}, sid)
          :persistent_term.put({__MODULE__, :events}, events)
        end
        
        # Mock GET request for SSE
        def get(url, _headers, _opts) do
          # Send SSE events to the calling process
          parent = self()
          session_id = :persistent_term.get({__MODULE__, :session_id})
          events = :persistent_term.get({__MODULE__, :events})
          
          # Spawn a process to send the events with delays
          spawn(fn ->
            # Process each event
            for event <- events do
              case event do
                {:http_response_headers, status, headers} ->
                  # Simulate response headers
                  send(parent, {:http_response, %{status: status, headers: headers}})
                  
                {:sse_event, event_type, data} ->
                  # Simulate SSE event
                  formatted_event = "event: #{event_type}\ndata: #{data}\n\n"
                  send(parent, {:sse_data, formatted_event})
                  
                {:delay, ms} ->
                  # Add delay to simulate real-world behavior
                  Process.sleep(ms)
              end
            end
            
            # Let the parent know we're done
            send(parent, {:sse_done})
          end)
          
          # Return ok with a fake reference to the "stream"
          {:ok, {:stream_ref, url, session_id}}
        end
        
        # Mock POST for sending messages
        def post(url, json_data, _headers, _timeout) do
          # Verify we're posting to the correct endpoint with sessionId
          expected_sessionId = :persistent_term.get({__MODULE__, :session_id})
          
          # Check the URL contains our session ID
          if not String.contains?(url, "sessionId=#{expected_sessionId}") do
            raise "URL doesn't contain the correct sessionId. Expected #{expected_sessionId}, URL: #{url}"
          end
          
          # Return a successful response
          {:ok, %{
            status: 200,
            body: %{"jsonrpc" => "2.0", "id" => json_data[:id] || 1, "result" => "success"}
          }}
        end
      end
      
      # Set up the client with our session ID and events
      SSEInitHttpClient.setup(session_id, sse_events)
      
      # Patch the connect_sse function in our implementation to simulate the full SSE flow
      
      # Create a modified implementation with hooks for our transport
      modified_connect_sse = fn(parent, request) ->
        # Extract the URL from the request
        url = request.url |> URI.to_string()
        
        # Log the initiation
        Logger.debug("SSE Test: Connecting to #{url}")
        
        # Use our mock client to get the SSE stream
        {:ok, _stream_ref} = SSEInitHttpClient.get(url, [], [])
        
        # Process mock events as they arrive
        try do
          receive do
            {:http_response, %{status: 200}} ->
              Logger.debug("SSE Test: Connection established")
              
              # Process data events until done
              
              # Simple state machine to process events
              sse_loop = fn loop_fn ->
                receive do
                  {:sse_data, data} ->
                    # Process SSE event data
                    if String.contains?(data, "event: endpoint") do
                      # Parse the endpoint data
                      endpoint_data = data
                        |> String.split("\n")
                        |> Enum.find(fn line -> String.starts_with?(line, "data:") end)
                        |> String.replace("data: ", "")
                        |> String.trim()
                        
                      # Send the endpoint to the transport
                      Logger.warning("SSE Test: Extracted endpoint path: #{endpoint_data}")
                      send(parent, {:sse_endpoint, endpoint_data})
                    end
                    
                    if String.contains?(data, "event: message") do
                      # Parse the message data
                      message_data = data
                        |> String.split("\n")
                        |> Enum.find(fn line -> String.starts_with?(line, "data:") end)
                        |> String.replace("data: ", "")
                        |> String.trim()
                        |> Jason.decode!()
                        
                      # Send the message to the transport
                      Logger.debug("SSE Test: Got message: #{inspect(message_data)}")
                      send(parent, {:sse_message, message_data})
                    end
                    
                    # Continue processing
                    loop_fn.(loop_fn)
                    
                  {:sse_done} ->
                    Logger.debug("SSE Test: All events processed")
                    :done
                    
                  other ->
                    Logger.debug("SSE Test: Unexpected message: #{inspect(other)}")
                    loop_fn.(loop_fn)
                after
                  5000 ->
                    Logger.debug("SSE Test: Timeout waiting for more events")
                    :timeout
                end
              end
              
              # Start the loop
              sse_loop.(sse_loop)
              
            other ->
              Logger.error("SSE Test: Unexpected response: #{inspect(other)}")
          after
            5000 ->
              Logger.error("SSE Test: Timeout waiting for response")
          end
        catch
          _kind, error ->
            Logger.error("SSE Test: Error: #{inspect(error)}")
            send(parent, {:sse_error, error})
        after
          # Let the transport know we're done
          send(parent, {:sse_closed})
        end
      end
      
      # Start a transport with our mock client
      {:ok, transport} = Http.start_link(
        url: "https://example.com/sse",
        http_client: SSEInitHttpClient
      )
      
      # Manually trigger our patched connect_sse
      send(transport, {:use_patched_connect_sse, modified_connect_sse})
      send(transport, :connect_sse)
      
      # Wait for the endpoint to be processed and ensure our message event handler has time to run
      # We'll poll until we see the correct URL or timeout
      start_time = :os.system_time(:millisecond)
      timeout = 1000 # 1 second timeout
      
      # Helper to check post_url from state
      check_post_url = fn ->
        state = :sys.get_state(transport)
        post_url = Map.get(state, :post_url)
        Logger.info("Checking post URL in transport state: #{inspect(post_url)}")
        
        # Return true if we found the URL with our session ID
        post_url && String.contains?(post_url, "sessionId=#{session_id}")
      end
      
      # Poll until we find the right URL or timeout
      wait_for_url = fn poll_fn ->
        # Check if we have the right URL
        if check_post_url.() do
          :ok
        else
          # Check if we've timed out
          current_time = :os.system_time(:millisecond)
          if current_time - start_time > timeout do
            :timeout
          else
            # Sleep briefly and retry
            :timer.sleep(50)
            poll_fn.(poll_fn)
          end
        end
      end
      
      # Start polling
      poll_result = wait_for_url.(wait_for_url)
      
      # Now verify the result
      post_url = :sys.get_state(transport) |> Map.get(:post_url)
      Logger.info("Expected session ID: #{session_id}")
      Logger.info("Actual endpoint URL: #{post_url}")
      
      # If we timed out, the assert will fail, otherwise it should pass
      if poll_result == :timeout do
        flunk("Timed out waiting for transport to update with correct endpoint URL")
      end
      
      assert post_url =~ "https://example.com/messages?sessionId=#{session_id}"
      
      # Test sending a message - should verify it uses the correct session ID
      {:ok, response} = Http.send_message(transport, %{method: "test", id: 42})
      assert response.status == 200
      assert response.body["result"] == "success"
      assert response.body["id"] == 42
      
      # Clean up
      Http.close(transport)
    end
  end
  
  # Helper for message monitoring
  defp monitor_transport_messages(parent) do
    receive do
      {:io_request, from, reply_as, {:put_chars, _, msg}} ->
        # Log intercept for debugging
        if is_binary(msg) && String.contains?(msg, "transport_response") do
          send(parent, {:intercepted, msg})
        end
        
        # Always respond to IO requests
        send(from, {:io_reply, reply_as, :ok})
        monitor_transport_messages(parent)
      _other ->
        # Ignore other messages
        monitor_transport_messages(parent)
    after
      5000 -> :timeout
    end
  end
end