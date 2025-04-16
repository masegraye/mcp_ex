defmodule MCPEx.Sampling.RateLimiterTest do
  use ExUnit.Case, async: false # Not async due to shared GenServer state
  
  alias MCPEx.Sampling.RateLimiter
  
  setup do
    # Start a named RateLimiter for this test
    {:ok, limiter} = RateLimiter.start_link(name: :test_rate_limiter)
    
    # Start with an empty state
    client_id = "test_client_#{:rand.uniform(1000)}"
    
    on_exit(fn ->
      if Process.alive?(limiter) do
        Process.exit(limiter, :normal)
      end
    end)
    
    {:ok, %{limiter: limiter, client_id: client_id}}
  end
  
  describe "check_limit/3" do
    test "allows requests within limits", %{limiter: limiter, client_id: client_id} do
      # No limits defined
      assert :ok = RateLimiter.check_limit(limiter, client_id)
      
      # Within defined limits
      assert :ok = RateLimiter.check_limit(limiter, client_id, requests_per_minute: 10)
    end
    
    test "rejects requests over limits", %{limiter: limiter, client_id: client_id} do
      # Record 5 requests
      for _ <- 1..5 do
        RateLimiter.record_request(limiter, client_id)
      end
      
      # Check with a limit of 3 requests per minute
      assert {:error, _reason} = RateLimiter.check_limit(limiter, client_id, requests_per_minute: 3)
      
      # Check with a limit of 10 requests per minute (should pass)
      assert :ok = RateLimiter.check_limit(limiter, client_id, requests_per_minute: 10)
    end
  end
  
  describe "record_request/2" do
    test "records requests for a client", %{limiter: limiter, client_id: client_id} do
      # Initial state
      initial_stats = RateLimiter.get_stats(limiter, client_id)
      assert initial_stats.total_requests == 0
      
      # Record some requests
      for _ <- 1..3 do
        RateLimiter.record_request(limiter, client_id)
      end
      
      # Check updated stats
      updated_stats = RateLimiter.get_stats(limiter, client_id)
      assert updated_stats.total_requests == 3
      assert updated_stats.requests_last_minute == 3
    end
  end
  
  describe "get_stats/2" do
    test "returns stats for different time windows", %{limiter: limiter, client_id: client_id} do
      # Record some requests
      for _ <- 1..5 do
        RateLimiter.record_request(limiter, client_id)
      end
      
      # Check stats
      stats = RateLimiter.get_stats(limiter, client_id)
      
      assert stats.total_requests == 5
      assert stats.requests_last_minute == 5
      assert stats.requests_last_hour == 5
      assert stats.requests_last_day == 5
    end
    
    test "returns empty stats for unknown clients", %{limiter: limiter} do
      unknown_client = "unknown_client"
      
      stats = RateLimiter.get_stats(limiter, unknown_client)
      
      assert stats.total_requests == 0
      assert stats.requests_last_minute == 0
    end
  end
  
  describe "cleanup" do
    test "retains recent requests", %{limiter: limiter, client_id: client_id} do
      # Record some requests
      for _ <- 1..3 do
        RateLimiter.record_request(limiter, client_id)
      end
      
      # Send cleanup message manually
      send(limiter, :cleanup)
      
      # Allow cleanup to process
      :timer.sleep(50)
      
      # Check stats - should still have the requests
      stats = RateLimiter.get_stats(limiter, client_id)
      assert stats.total_requests == 3
    end
    
    test "multiple clients are tracked separately", %{limiter: limiter, client_id: client_id} do
      client_id2 = "another_client"
      
      # Record requests for first client
      for _ <- 1..3 do
        RateLimiter.record_request(limiter, client_id)
      end
      
      # Record requests for second client
      for _ <- 1..5 do
        RateLimiter.record_request(limiter, client_id2)
      end
      
      # Check stats for each client
      stats1 = RateLimiter.get_stats(limiter, client_id)
      stats2 = RateLimiter.get_stats(limiter, client_id2)
      
      assert stats1.total_requests == 3
      assert stats2.total_requests == 5
    end
  end
end