defmodule MCPEx.Transport.Http do
  @moduledoc """
  Implementation of the MCP transport over HTTP with Server-Sent Events (SSE).

  This transport follows the Model Context Protocol (MCP) HTTP transport specification:
  
  1. **SSE Connection**: The client connects to an SSE endpoint (e.g., `https://example.com/sse`) to receive server events
  2. **Message Endpoint Notification**: The server sends a special `endpoint` event via SSE with the following format:
     ```
     event: endpoint
     data: /messages?sessionId=abc123
     ```
  3. **Message Endpoint Construction**: The client constructs the full message endpoint URL by using the same origin as the SSE connection and appending the received path and query string (e.g., `https://example.com/messages?sessionId=abc123`)
  4. **Message Exchange**: The client sends all JSON-RPC messages as HTTP POST requests to this constructed message endpoint

  This approach allows the server to dynamically configure where messages should be sent,
  supporting load balancing and session routing while maintaining the same origin. The transport manages this by:
  
  - Establishing and maintaining the SSE connection
  - Processing the endpoint event to configure the message endpoint
  - Sending all client messages to the configured endpoint
  - Handling server messages received via the SSE stream
  
  This transport follows Req's API patterns, making it easy to test with custom HTTP clients.
  
  ## Testing
  
  There are two main approaches for testing code that uses this transport:
  
  1. Using a custom HTTP client (recommended):
  ```elixir
  # Define a mock HTTP client for testing
  defmodule MockHttpClient do
    def post(_url, json_data, _headers, _timeout) do
      # Verify request data
      assert json_data.method == "test"
      
      # Return a mock response
      {:ok, %{status: 200, body: %{"result" => "success"}}}
    end
  end
  
  # Start the transport with the mock client
  {:ok, transport} = Http.start_link(
    url: "https://example.com/sse",
    http_client: MockHttpClient
  )
  
  # Simulate the SSE message endpoint notification
  # Note: only the path is sent, the client constructs the full URL
  send(transport, {:sse_endpoint, "/messages?sessionId=abc123"})
  
  # Test sending a message
  {:ok, response} = Http.send_message(transport, %{method: "test"})
  assert response.status == 200
  assert response.body["result"] == "success"
  ```
  
  2. Using Req.Test (for testing without process boundaries):
  ```elixir
  # Set up Req.Test
  Req.Test.stub(:test_stub, fn conn ->
    assert conn.body["method"] == "test"
    %{conn | status: 200, body: %{"result" => "success"}}
  end)
  
  # Create a request with the test plug
  req = Http.new(
    url: "https://example.com/sse",
    plug: {Req.Test, :test_stub}
  )
  
  # This approach works for direct Req calls but has limitations
  # with the GenServer process boundary in the transport
  ```
  
  See product/docs/010.01.req-usage.md for more detailed examples and patterns.
  """

  use GenServer
  require Logger

  @doc """
  Creates a new HTTP transport request configuration.

  ## Options

  * `:url` - The URL of the MCP server SSE endpoint (required)
  * `:headers` - Additional HTTP headers to include in requests
  * `:timeout` - Request timeout in milliseconds (default: 30000)
  * `:http_client` - Optional custom HTTP client module for testing (see example in tests)
  * Plus any other options from Req.new/1

  ## Returns

  * `%Req.Request{}` - A request configuration for the HTTP transport

  ## Examples

      iex> req = MCPEx.Transport.Http.new(url: "https://example.com/sse")
      %Req.Request{}
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(options) do
    url = Keyword.fetch!(options, :url)
    headers = Keyword.get(options, :headers, [])
    timeout = Keyword.get(options, :timeout, 30_000)
    content_type = {"Content-Type", "application/json"}
    
    # Create a default Req configuration
    req_options = Keyword.drop(options, [:url, :headers, :timeout, :http_client])
    
    req = Req.new()
    req = Req.merge(req, [
      base_url: url,
      headers: [content_type | headers],
      receive_timeout: timeout
    ])
    
    # Add any additional options
    Enum.reduce(req_options, req, fn {key, value}, acc ->
      Req.merge(acc, [{key, value}])
    end)
  end

  @doc """
  Starts a new HTTP transport as a linked process.

  ## Options

  * `:request` - A Req.Request struct created with Http.new/1
  * `:http_client` - Optional custom HTTP client module for testing
  * Or any option accepted by Http.new/1

  ## Returns

  * `{:ok, pid}` - The transport was started successfully
  * `{:error, reason}` - Failed to start the transport

  ## Examples

      # Using Http.new
      iex> req = MCPEx.Transport.Http.new(url: "https://example.com/sse")
      iex> {:ok, pid} = MCPEx.Transport.Http.start_link(request: req)

      # Or directly with options
      iex> {:ok, pid} = MCPEx.Transport.Http.start_link(url: "https://example.com/sse")
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options) do
    # Either use the provided request or create one from options
    init_state = case {Keyword.fetch(options, :request), Keyword.fetch(options, :http_client)} do
      {{:ok, req}, {:ok, client}} -> 
        %{request: req, http_client: client}
      {{:ok, req}, _} -> 
        %{request: req}
      {_, {:ok, client}} -> 
        %{request: new(options), http_client: client}
      {_, _} -> 
        %{request: new(options)}
    end
    
    GenServer.start_link(__MODULE__, init_state)
  end

  @impl true
  def init(options) do
    request = case options do
      %{request: req} -> req
      other when is_map(other) -> 
        new(Map.to_list(other))
    end
    
    # Get optional HTTP client
    http_client = case options do
      %{http_client: client} -> client
      _ -> nil
    end
    
    # Initialize client state
    state = %{
      request: request,
      post_url: nil,  # Will be set when we receive the endpoint event
      sse_request: nil,  # Will hold the SSE request process
      connected: false,
      http_client: http_client
    }

    # Start SSE connection asynchronously
    send(self(), :connect_sse)

    {:ok, state}
  end

  @doc """
  Sends a message to the server via HTTP POST.

  ## Parameters

  * `pid` - The transport process
  * `message` - The message to send (string or map)

  ## Returns

  * `{:ok, response}` - The message was sent successfully with the full response
  * `{:error, reason}` - Failed to send the message

  ## Examples

      iex> Http.send_message(pid, ~s({"jsonrpc":"2.0","method":"test"}))
      {:ok, %{status: 200, body: %{...}}}

      iex> Http.send_message(pid, %{jsonrpc: "2.0", method: "test"})
      {:ok, %{status: 200, body: %{...}}}
  """
  @spec send_message(pid(), String.t() | map()) :: {:ok, map()} | {:error, term()}
  def send_message(pid, message) do
    GenServer.call(pid, {:send, message})
  end

  @doc """
  Closes the transport connection.

  ## Parameters

  * `pid` - The transport process

  ## Returns

  * `:ok` - The connection was closed successfully
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.call(pid, :close)
  end

  @impl true
  def handle_call({:send, _message}, _from, %{post_url: nil} = state) do
    {:reply, {:error, "No POST endpoint available, connection not established"}, state}
  end

  @impl true
  def handle_call({:send, message}, _from, %{post_url: post_url} = state) do
    # Process message based on type
    json_data = case message do
      str when is_binary(str) -> 
        case Jason.decode(str) do
          {:ok, decoded} -> decoded
          {:error, _} -> %{text: str}  # Treat as plain text if not valid JSON
        end
      map when is_map(map) -> map
    end
    
    # If we have a custom HTTP client for testing, use it
    response = if state.http_client do
      state.http_client.post(post_url, json_data, state.request.options[:headers], state.request.options[:receive_timeout])
    else
      # Otherwise create a request using Req
      post_request = Req.new()
      
      # Add the POST URL and json data
      post_request = Req.merge(post_request, [
        base_url: post_url,
        json: json_data
      ])
      
      # Copy headers and timeout from the original request
      post_request = Req.merge(post_request, [
        headers: state.request.options[:headers] || [],
        receive_timeout: state.request.options[:receive_timeout] || 30_000
      ])
      
      # Copy any testing plugins (like Req.Test)
      post_request = if state.request.options[:plug] do
        Req.merge(post_request, [
          plug: state.request.options[:plug]
        ])
      else
        post_request
      end
      
      # Send the actual request
      Req.post(post_request)
    end
    
    # Process the response
    case response do
      {:ok, response = %{status: status}} when status in 200..299 ->
        {:reply, {:ok, response}, state}

      {:ok, response = %{status: status}} ->
        Logger.error("HTTP transport error: status code #{status}")
        {:reply, {:error, response}, state}

      {:error, _} = error ->
        Logger.error("HTTP transport error: #{inspect(error)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:close, _from, state) do
    # Clean up SSE connection if it exists
    if state.sse_request && Process.alive?(state.sse_request) do
      # Send exit signal to SSE process
      Process.exit(state.sse_request, :normal)
    end

    {:reply, :ok, %{state | sse_request: nil, connected: false}}
  end

  @impl true
  def handle_info(:connect_sse, %{patched_connect_sse: patched_fn} = state) when is_function(patched_fn, 2) do
    # Use the patched connect_sse function for testing
    parent = self()
    
    sse_pid = spawn_link(fn -> 
      patched_fn.(parent, state.request) 
    end)
    
    {:noreply, %{state | sse_request: sse_pid}}
  end
  
  @impl true
  def handle_info(:connect_sse, state) do
    # Start SSE connection with the normal implementation
    parent = self()
    
    sse_pid = spawn_link(fn -> 
      connect_sse(parent, state.request) 
    end)
    
    {:noreply, %{state | sse_request: sse_pid}}
  end
  
  @impl true
  def handle_info({:use_patched_connect_sse, patched_fn}, state) when is_function(patched_fn, 2) do
    # Store the patched connect_sse function for testing
    {:noreply, Map.put(state, :patched_connect_sse, patched_fn)}
  end

  @impl true
  def handle_info({:sse_endpoint, endpoint_path}, state) do
    # Get the base URL from the SSE request
    base_url = state.request.options[:base_url]
    uri = URI.parse(base_url)
    
    # Handle edge cases for endpoint_path
    normalized_path = case endpoint_path do
      # Empty string - default to root path
      "" -> "/"
      # Already provided - use as is
      _ -> endpoint_path
    end
    
    # Parse the endpoint path to properly handle query params and fragments
    endpoint_uri = URI.parse(normalized_path)
    
    # Construct the full message endpoint URL by taking the origin from the SSE URL
    # and appending the path received in the endpoint event
    message_endpoint = URI.to_string(%{
      uri | 
      path: endpoint_uri.path,
      query: endpoint_uri.query,
      fragment: endpoint_uri.fragment
    })
    
    Logger.debug("Received endpoint path: #{endpoint_path}")
    Logger.debug("Constructed message endpoint: #{message_endpoint}")
    
    {:noreply, %{state | post_url: message_endpoint, connected: true}}
  end

  @impl true
  def handle_info({:sse_message, message}, state) do
    # Forward the message to client code
    Process.send(self(), {:transport_response, message}, [])
    {:noreply, state}
  end

  @impl true
  def handle_info({:sse_error, reason}, state) do
    Logger.error("SSE connection error: #{inspect(reason)}")
    # Try to reconnect after a delay
    Process.send_after(self(), :connect_sse, 5000)
    {:noreply, %{state | sse_request: nil, connected: false}}
  end

  @impl true
  def handle_info({:sse_closed}, state) do
    Logger.info("SSE connection closed")
    # Try to reconnect after a delay
    Process.send_after(self(), :connect_sse, 5000)
    {:noreply, %{state | sse_request: nil, connected: false}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in HTTP transport: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helper functions

  # Establishes SSE connection
  defp connect_sse(parent, request) do
    url = request.url |> URI.to_string()
    Logger.debug("Connecting to SSE endpoint: #{url}")
    
    try do
      # IMPORTANT: This is a simulated SSE connection for initial testing/development.
      # In a production environment, this would need to be replaced with a proper 
      # Server-Sent Events implementation using Req's streaming functionality.
      #
      # The actual implementation would:
      # 1. Set up an HTTP GET request to the SSE endpoint with appropriate headers
      # 2. Use Req's streaming capabilities to read the response body in chunks
      # 3. Parse SSE events (lines starting with "event:" and "data:")
      # 4. Handle special events like "endpoint" to configure the message endpoint 
      # 5. Handle message events to forward to the client application
      #
      # Example implementation outline:
      #
      # stream_req = request
      #   |> Req.merge([
      #     headers: [{"Accept", "text/event-stream"}]
      #   ])
      #   |> Req.Request.append_response_steps(
      #     handle_sse: fn response ->
      #       # Set up stream processing
      #       stream_ref = response.ref
      #       buffer = ""
      #       
      #       # Process each chunk as it arrives
      #       receive_loop = fn loop_fn, buf ->
      #         receive do
      #           {:data, ^stream_ref, data} -> 
      #             # Append data to buffer and process any complete events
      #             updated_buf = buf <> data
      #             {events, remaining_buf} = parse_sse_events(updated_buf)
      #             
      #             # Process each complete event
      #             for {event_type, event_data} <- events do
      #               case event_type do
      #                 "endpoint" -> send(parent, {:sse_endpoint, event_data})
      #                 "message" -> 
      #                   case Jason.decode(event_data) do
      #                     {:ok, decoded} -> send(parent, {:sse_message, decoded})
      #                     _ -> nil
      #                   end
      #                 _ -> nil
      #               end
      #             end
      #             
      #             # Continue with remaining buffer
      #             loop_fn.(loop_fn, remaining_buf)
      #             
      #           # Handle other message types...
      #         end
      #       end
      #       
      #       # Start the processing loop
      #       receive_loop.(receive_loop, "")
      #       response
      #     end
      #   )
      # 
      # Req.get!(stream_req)
      
      # Send a simulated endpoint event after a short delay
      # In a real implementation, this would come from the SSE event
      # The endpoint event only includes path and query string, not the full URL
      Process.sleep(100)
      send(parent, {:sse_endpoint, "/messages"})
    catch
      :error, reason ->
        send(parent, {:sse_error, reason})
      :exit, reason ->
        send(parent, {:sse_error, reason})
    after
      send(parent, {:sse_closed})
    end
  end
end