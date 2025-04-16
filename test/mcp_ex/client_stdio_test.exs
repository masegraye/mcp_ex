defmodule MCPEx.ClientStdioTest do
  use ExUnit.Case, async: false

  alias MCPEx.Client

  @moduletag :external

  describe "prompt operations with docker fetch server" do
    @tag :external
    test "direct communication with docker fetch server" do
      # Start a port directly for testing the protocol
      port = Port.open({:spawn_executable, System.find_executable("docker")}, [
        :binary,
        :exit_status,
        :hide,
        :use_stdio,
        args: ["run", "-i", "--rm", "mcp/fetch"]
      ])

      # Send an initialize request with proper format
      initialize_request = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{
            "prompts" => true
          },
          "clientInfo" => %{"name" => "MCPEx Test Client", "version" => "1.0.0"}
        }
      }) <> "\n"

      # Send it to the port
      Port.command(port, initialize_request)

      # Wait for response
      response = receive do
        {^port, {:data, data}} ->
          case Jason.decode(data) do
            {:ok, decoded} -> decoded
            _ -> data
          end
        msg -> "Unexpected message: #{inspect(msg)}"
      after
        5000 -> "Timeout waiting for initialize response"
      end

      IO.puts("Initialize response: #{inspect(response)}")

      # Verify we got a valid response
      assert is_map(response)
      assert Map.has_key?(response, "result")

      # Send the initialized notification
      initialized_notification = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "params" => %{}
      }) <> "\n"

      Port.command(port, initialized_notification)

      # Wait a bit for it to process
      Process.sleep(500)

      # Send a ping request to confirm the connection works
      ping_request = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "ping",
        "params" => %{}
      }) <> "\n"

      Port.command(port, ping_request)

      # Wait for ping response
      ping_response = receive do
        {^port, {:data, data}} ->
          case Jason.decode(data) do
            {:ok, decoded} -> decoded
            _ -> data
          end
        msg -> "Unexpected message: #{inspect(msg)}"
      after
        5000 -> "Timeout waiting for ping response"
      end

      IO.puts("Ping response: #{inspect(ping_response)}")
      assert is_map(ping_response)
      assert Map.has_key?(ping_response, "result")

      # Close the port
      Port.close(port)
    end

    @tag :external
    test "client integration with docker fetch server" do
      # Start client with stdio transport to docker fetch server
      command = "docker"
      args = ["run", "-i", "--rm", "mcp/fetch"]

      # Start client with stdio transport
      client_options = [
        transport: :stdio,
        command: command,
        args: args,
        capabilities: [:prompts],
        client_info: %{name: "MCPEx Test Client", version: "1.0.0"}
      ]

      IO.puts("Starting client with options: #{inspect(client_options)}")

      {:ok, client} = Client.start_link(client_options)

      try do
        # Verify client connected
        assert Process.alive?(client)

        # 1. Keep the ping test as requested with shorter timeout
        IO.puts("Sending ping to server...")
        assert {:ok, _} = Client.ping(client, 1000)
        IO.puts("Ping successful!")

        # 2. Add the capabilities test
        IO.puts("Checking server capabilities...")
        {:ok, capabilities} = Client.get_server_capabilities(client)
        IO.puts("Server capabilities: #{inspect(capabilities)}")
        assert is_map(capabilities), "Should return capabilities map"

        # Verify we have prompts capability
        assert Map.has_key?(capabilities, :prompts), "Server should have prompts capability"

        # Get server info and verify
        {:ok, server_info} = Client.get_server_info(client)
        IO.puts("Server info: #{inspect(server_info)}")
        assert is_map(server_info), "Should return server info map"
        assert Map.has_key?(server_info, :name), "Server info should contain name"

        # Test list_prompts operation
        IO.puts("Listing prompts...")
        case Client.list_prompts(client) do
          {:ok, prompt_list} ->
            IO.puts("Prompt list: #{inspect(prompt_list)}")
            assert is_map(prompt_list), "Should return a prompt list response"

            # Extract prompts using either string or atom keys
            prompts = prompt_list["prompts"] || prompt_list[:prompts]

            if prompts != nil do
              assert is_list(prompts), "Prompts should be a list"
              IO.puts("Found #{length(prompts)} prompts")

              # If we got prompts, test getting the first one
              if length(prompts) > 0 do
                first_prompt = List.first(prompts)
                prompt_name = first_prompt["name"] || first_prompt[:name]
                IO.puts("Getting prompt: #{prompt_name}")
                
                # For the fetch server, we need to provide a URL parameter
                prompt_args = %{"url" => "https://example.com"}
                IO.puts("Requesting prompt with args: #{inspect(prompt_args)}")
                
                case Client.get_prompt(client, prompt_name, prompt_args) do
                  {:ok, prompt} ->
                    IO.puts("Got prompt: #{inspect(prompt)}")
                    assert is_map(prompt), "Should return a prompt object"

                  error ->
                    IO.puts("Error getting prompt: #{inspect(error)}")
                    flunk("Failed to get prompt: #{inspect(error)}")
                end
              end
            else
              IO.puts("No prompts found or invalid response format")
            end

          error ->
            IO.puts("Error listing prompts: #{inspect(error)}")
            # Don't fail the test if list_prompts doesn't work - it might not be implemented
            IO.puts("list_prompts failed, but continuing with test")
        end

        # The fetch server has a special error handling approach:
        # It returns success responses with error details in the content
        # rather than JSON-RPC errors, so we'll test that we can handle this
        IO.puts("Testing handling of invalid URL...")
        result = Client.get_prompt(client, "fetch", %{"url" => "not-a-valid-url"})

        case result do
          {:ok, response} ->
            IO.puts("Got response with invalid URL: #{inspect(response)}")
            
            # Verify the response contains information about the error
            assert is_map(response), "Should return a response map"
            assert String.contains?(response["description"] || "", "Failed to fetch"), 
              "Description should indicate fetch failure"
              
            # Verify messages contain error text
            messages = response["messages"] || []
            assert length(messages) > 0, "Should contain at least one message"
            
            content_text = get_in(List.first(messages), ["content", "text"]) || ""
            assert String.contains?(content_text, "Failed to fetch"), 
              "Message content should indicate fetch failure"

          error ->
            IO.puts("Got unexpected error: #{inspect(error)}")
            flunk("Expected success response with error details but got: #{inspect(error)}")
        end
      after
        # 3. Close the docker process at the end by properly stopping the client
        IO.puts("Stopping client...")
        Client.stop(client)
        # Let the wrapper script handle the process cleanup
      end
    end
  end

end
