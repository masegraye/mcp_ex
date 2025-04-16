defmodule MCPEx.Transport.Test do
  @moduledoc """
  Test implementation of the MCP transport for integration testing.
  
  This transport operates fully in memory and connects to an MCPEx.Transport.TestServer
  instance to simulate the server side of the protocol.
  
  ## Features
  
  * In-memory communication with no external dependencies
  * Controllable message flow and timing
  * Observable message exchange for testing
  * Configurable error scenarios
  * Complete protocol simulation
  
  ## Usage
  
  ```elixir
  # Create a test server
  server = MCPEx.Transport.TestServer.new(
    capabilities: [:resources, :tools]
  )
  
  # Create a test transport connected to this server
  {:ok, transport} = MCPEx.Transport.Test.start_link(server: server)
  
  # Register a message receiver (optional)
  MCPEx.Transport.Test.register_message_receiver(transport, self())
  
  # Send a message and get response
  {:ok, response} = MCPEx.Transport.send(transport, json_encoded_message)
  ```
  """
  
  use GenServer
  require Logger
  
  defstruct [
    # Connection state
    server: nil,
    client_ref: nil,
    connected: false,
    
    # Message handling
    message_receiver: nil,
    pending_requests: %{},
    next_id: 1,
    
    # Configuration
    config: %{},
    
    # For testing/debugging
    log: []
  ]
  
  @type t :: %__MODULE__{
    server: MCPEx.Transport.TestServer.t() | nil,
    client_ref: reference() | nil,
    connected: boolean(),
    message_receiver: pid() | nil,
    pending_requests: map(),
    next_id: integer(),
    config: map(),
    log: list()
  }
  
  @doc """
  Starts a new test transport as a linked process.
  
  ## Options
  
  * `:server` - The MCPEx.Transport.TestServer instance to connect to (required)
  * `:auto_connect` - Whether to automatically connect to the server (default: true)
  * `:config` - Additional configuration options
  
  ## Returns
  
  * `{:ok, pid}` - The transport was started successfully
  * `{:error, reason}` - Failed to start the transport
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end
  
  @doc """
  Creates a new test transport instance without starting a process.
  
  ## Options
  
  * `:server` - The MCPEx.Transport.TestServer instance to connect to (required)
  * `:config` - Additional configuration options
  
  ## Returns
  
  * A new TestTransport struct
  """
  @spec new(keyword()) :: t()
  def new(options) do
    server = Keyword.fetch!(options, :server)
    config = Keyword.get(options, :config, %{})
    
    %__MODULE__{
      server: server,
      client_ref: nil,
      connected: false,
      message_receiver: nil,
      pending_requests: %{},
      next_id: 1,
      config: config,
      log: []
    }
  end
  
  @doc """
  Registers a process to receive message notifications.
  
  The registered process will receive `{:message, message}` tuples
  for all messages received from the server.
  
  ## Parameters
  
  * `transport` - The transport process
  * `receiver` - The process to receive notifications
  
  ## Returns
  
  * `:ok`
  """
  @spec register_message_receiver(pid(), pid()) :: :ok
  def register_message_receiver(transport, receiver) do
    GenServer.call(transport, {:register_message_receiver, receiver})
  end
  
  @doc """
  Sends a message to the server and waits for a response.
  
  ## Parameters
  
  * `transport` - The transport process
  * `message` - The message to send, either as a map or JSON string
  
  ## Returns
  
  * `{:ok, response}` - The response from the server
  * `{:error, reason}` - Failed to send the message or receive a response
  """
  @spec send_message(pid(), map() | String.t()) :: {:ok, map()} | {:error, term()}
  def send_message(transport, message) do
    GenServer.call(transport, {:send, message})
  end
  
  @doc """
  Checks if the transport is connected to the server.
  
  ## Parameters
  
  * `transport` - The transport process
  
  ## Returns
  
  * `true` or `false`
  """
  @spec connected?(pid()) :: boolean()
  def connected?(transport) do
    GenServer.call(transport, :connected?)
  end
  
  @doc """
  Gets the current message log for debugging/testing purposes.
  
  ## Parameters
  
  * `transport` - The transport process
  
  ## Returns
  
  * List of log entries
  """
  @spec get_log(pid()) :: list()
  def get_log(transport) do
    GenServer.call(transport, :get_log)
  end
  
  @doc """
  Records a session of message exchanges for later replay.
  
  ## Parameters
  
  * `fun` - Function to execute during recording
  
  ## Returns
  
  * `{:ok, recording}` - The recorded session
  * `{:error, reason}` - Failed to record the session
  """
  @spec record_session((-> any())) :: {:ok, term()} | {:error, term()}
  def record_session(fun) when is_function(fun, 0) do
    # Create a server with recording enabled
    server = MCPEx.Transport.TestServer.new(
      record_mode: true
    )
    
    # Create a transport
    {:ok, transport} = start_link(server: server)
    
    try do
      # Execute the function
      fun.()
      
      # Extract the recording
      recording = MCPEx.Transport.TestServer.get_recording(server)
      {:ok, recording}
    catch
      kind, reason ->
        {:error, {kind, reason, __STACKTRACE__}}
    after
      # Clean up
      GenServer.call(transport, :close)
    end
  end
  
  @doc """
  Replays a previously recorded session.
  
  ## Parameters
  
  * `recording` - Recording from record_session
  
  ## Returns
  
  * `{:ok, transport}` - Transport for the replayed session
  * `{:error, reason}` - Failed to replay the session
  """
  @spec replay_session(term()) :: {:ok, pid()} | {:error, term()}
  def replay_session(recording) do
    # Create a server in replay mode
    server = MCPEx.Transport.TestServer.new(
      replay_mode: true,
      recording: recording
    )
    
    # Create a transport
    start_link(server: server)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(options) do
    server = Keyword.fetch!(options, :server)
    auto_connect = Keyword.get(options, :auto_connect, true)
    config = Keyword.get(options, :config, %{})
    
    state = %__MODULE__{
      server: server,
      client_ref: nil,
      connected: false,
      message_receiver: nil,
      pending_requests: %{},
      next_id: 1,
      config: config,
      log: []
    }
    
    # Connect to the server if auto_connect is true
    if auto_connect do
      {client_ref, updated_server} = MCPEx.Transport.TestServer.register_client(server, self())
      
      updated_state = %{state | 
        server: updated_server,
        client_ref: client_ref,
        connected: true
      }
      
      {:ok, add_log(updated_state, "Connected to test server")}
    else
      {:ok, state}
    end
  end
  
  @impl true
  def handle_call({:register_message_receiver, receiver}, _from, state) do
    updated_state = %{state | message_receiver: receiver}
    {:reply, :ok, add_log(updated_state, "Registered message receiver: #{inspect(receiver)}")}
  end
  
  @impl true
  def handle_call({:send, message}, from, state) when is_map(message) do
    # Encode the message to JSON
    case Jason.encode(message) do
      {:ok, json} ->
        handle_call({:send, json}, from, state)
      {:error, reason} ->
        {:reply, {:error, "Failed to encode message: #{inspect(reason)}"}, state}
    end
  end
  
  @impl true
  def handle_call({:send, _message}, _from, %{connected: false} = state) do
    {:reply, {:error, "Not connected to test server"}, state}
  end
  
  @impl true
  def handle_call({:send, message}, from, state) when is_binary(message) do
    # Decode the message to get the ID
    case Jason.decode(message) do
      {:ok, decoded} ->
        id = decoded["id"]
        
        if id do
          # Store the pending request
          pending = Map.put(state.pending_requests, id, from)
          updated_state = %{state | pending_requests: pending}
          updated_state = add_log(updated_state, "Sending message: #{inspect(decoded)}")
          
          # Send the message to the test server
          {response, updated_server} = MCPEx.Transport.TestServer.process_message(
            state.server,
            state.client_ref,
            message
          )
          
          updated_state = %{updated_state | server: updated_server}
          
          # If the response is immediate (not async), handle it now
          if is_map(response) do
            handle_response(response, updated_state)
          else
            # Otherwise wait for the async response
            {:noreply, updated_state}
          end
        else
          # No ID in the message, can't track request
          {:reply, {:error, "Message must have an 'id' field"}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, "Failed to decode message: #{inspect(reason)}"}, state}
    end
  end
  
  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end
  
  @impl true
  def handle_call(:get_log, _from, state) do
    {:reply, Enum.reverse(state.log), state}
  end
  
  @impl true
  def handle_call(:close, _from, state) do
    updated_state = if state.connected and state.client_ref do
      updated_server = MCPEx.Transport.TestServer.unregister_client(state.server, state.client_ref)
      %{state | server: updated_server, connected: false, client_ref: nil}
    else
      state
    end
    
    {:reply, :ok, add_log(updated_state, "Closed connection")}
  end
  
  @impl true
  def handle_info({:test_server_notification, notification}, state) do
    updated_state = add_log(state, "Received notification: #{inspect(notification)}")
    
    # Forward to message receiver if registered
    if state.message_receiver do
      send(state.message_receiver, {:message, notification})
    end
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:test_server_error, reason}, state) do
    updated_state = add_log(state, "Server error: #{inspect(reason)}")
    
    # Set as disconnected
    updated_state = %{updated_state | connected: false}
    
    # Fail all pending requests
    Enum.each(state.pending_requests, fn {_id, from} ->
      GenServer.reply(from, {:error, reason})
    end)
    
    # Notify message receiver if registered
    if state.message_receiver do
      send(state.message_receiver, {:error, reason})
    end
    
    {:noreply, %{updated_state | pending_requests: %{}}}
  end
  
  @impl true
  def handle_info(msg, state) do
    updated_state = add_log(state, "Unhandled message: #{inspect(msg)}")
    {:noreply, updated_state}
  end
  
  # Private helpers
  
  defp handle_response(response, state) when is_binary(response) do
    case Jason.decode(response) do
      {:ok, decoded} ->
        handle_response(decoded, state)
      {:error, reason} ->
        Logger.error("Failed to decode response: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  defp handle_response(response, state) when is_map(response) do
    updated_state = add_log(state, "Received response: #{inspect(response)}")
    
    # Extract the ID from the response
    id = response["id"]
    
    if id && Map.has_key?(state.pending_requests, id) do
      # Get the caller from pending requests
      {from, updated_pending} = Map.pop(state.pending_requests, id)
      updated_state = %{updated_state | pending_requests: updated_pending}
      
      # Reply to the caller
      GenServer.reply(from, {:ok, response})
      
      # Forward to message receiver if registered
      if state.message_receiver do
        send(state.message_receiver, {:message, response})
      end
      
      {:noreply, updated_state}
    else
      # If it's not a response to a pending request, treat as notification
      if state.message_receiver do
        send(state.message_receiver, {:message, response})
      end
      
      {:noreply, updated_state}
    end
  end
  
  defp handle_response({:error, reason}, state) do
    updated_state = add_log(state, "Error response: #{inspect(reason)}")
    
    # Since we don't know which request this error is for, fail all pending
    Enum.each(state.pending_requests, fn {_id, from} ->
      GenServer.reply(from, {:error, reason})
    end)
    
    # Notify message receiver if registered
    if state.message_receiver do
      send(state.message_receiver, {:error, reason})
    end
    
    {:noreply, %{updated_state | pending_requests: %{}}}
  end
  
  defp add_log(state, entry) do
    timestamp = :os.system_time(:millisecond)
    log_entry = {timestamp, entry}
    %{state | log: [log_entry | state.log]}
  end
end