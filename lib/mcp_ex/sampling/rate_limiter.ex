defmodule MCPEx.Sampling.RateLimiter do
  @moduledoc """
  Rate limiting for MCP sampling requests.
  
  This module provides functionality to track and enforce rate limits on
  sampling requests based on client identity, with configurable time windows
  and limits.
  """
  
  use GenServer
  require Logger
  
  @default_cleanup_interval 60_000 # 1 minute in milliseconds
  
  # Client API
  
  @doc """
  Starts the rate limiter server.
  
  ## Options
  
  * `:cleanup_interval` - Interval in milliseconds to run cleanup (default: 60_000)
  * `:name` - Name to register the server under (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Checks if a client is within rate limits.
  
  ## Parameters
  
  * `server` - The server or name to call
  * `client_id` - Identifier for the client
  * `options` - Rate limiting options
  
  ## Options
  
  * `:requests_per_minute` - Maximum requests allowed per minute
  * `:requests_per_hour` - Maximum requests allowed per hour
  * `:requests_per_day` - Maximum requests allowed per day
  
  ## Returns
  
  * `:ok` - The client is within rate limits
  * `{:error, reason}` - The client should be rate limited
  """
  def check_limit(server \\ __MODULE__, client_id, options \\ []) do
    GenServer.call(server, {:check_limit, client_id, options})
  end
  
  @doc """
  Records a request for a client.
  
  ## Parameters
  
  * `server` - The server or name to call
  * `client_id` - Identifier for the client
  
  ## Returns
  
  * `:ok` - The request was recorded
  """
  def record_request(server \\ __MODULE__, client_id) do
    GenServer.cast(server, {:record_request, client_id})
  end
  
  @doc """
  Gets current statistics for a client.
  
  ## Parameters
  
  * `server` - The server or name to call
  * `client_id` - Identifier for the client
  
  ## Returns
  
  * `stats` - Map with request counts for different time windows
  """
  def get_stats(server \\ __MODULE__, client_id) do
    GenServer.call(server, {:get_stats, client_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Table structure: %{client_id => [timestamps]}
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    
    # Schedule periodic cleanup
    if cleanup_interval > 0 do
      Process.send_after(self(), :cleanup, cleanup_interval)
    end
    
    {:ok, %{requests: %{}}}
  end
  
  @impl true
  def handle_call({:check_limit, client_id, options}, _from, state) do
    now = :os.system_time(:second)
    timestamps = Map.get(state.requests, client_id, [])
    
    # Check each time window
    result = cond do
      exceeds_limit?(timestamps, now, 60, Keyword.get(options, :requests_per_minute)) ->
        {:error, "Rate limit exceeded: too many requests per minute"}
        
      exceeds_limit?(timestamps, now, 3600, Keyword.get(options, :requests_per_hour)) ->
        {:error, "Rate limit exceeded: too many requests per hour"}
        
      exceeds_limit?(timestamps, now, 86400, Keyword.get(options, :requests_per_day)) ->
        {:error, "Rate limit exceeded: too many requests per day"}
        
      true ->
        :ok
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_stats, client_id}, _from, state) do
    now = :os.system_time(:second)
    timestamps = Map.get(state.requests, client_id, [])
    
    stats = %{
      requests_last_minute: count_in_window(timestamps, now, 60),
      requests_last_hour: count_in_window(timestamps, now, 3600),
      requests_last_day: count_in_window(timestamps, now, 86400),
      total_requests: length(timestamps)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record_request, client_id}, state) do
    now = :os.system_time(:second)
    timestamps = Map.get(state.requests, client_id, [])
    updated_timestamps = [now | timestamps]
    
    updated_requests = Map.put(state.requests, client_id, updated_timestamps)
    {:noreply, %{state | requests: updated_requests}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    now = :os.system_time(:second)
    cutoff = now - 86400 # Keep data for last 24 hours
    
    # Remove old entries
    updated_requests = Enum.reduce(state.requests, %{}, fn {client_id, timestamps}, acc ->
      recent_timestamps = Enum.filter(timestamps, fn ts -> ts >= cutoff end)
      
      if recent_timestamps == [] do
        # No recent requests, remove the client entirely
        acc
      else
        Map.put(acc, client_id, recent_timestamps)
      end
    end)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @default_cleanup_interval)
    
    {:noreply, %{state | requests: updated_requests}}
  end
  
  # Private helpers
  
  defp exceeds_limit?(timestamps, now, window_seconds, limit) do
    if limit do
      count = count_in_window(timestamps, now, window_seconds)
      count >= limit
    else
      false # No limit defined
    end
  end
  
  defp count_in_window(timestamps, now, window_seconds) do
    cutoff = now - window_seconds
    Enum.count(timestamps, fn ts -> ts >= cutoff end)
  end
end