defmodule MCPEx.ClientTest do
  use ExUnit.Case, async: true

  alias MCPEx.Client
  alias MCPEx.Transport.Test, as: TestTransport
  alias MCPEx.Transport.TestServer

  # Helper to create a test server with default capabilities
  defp create_test_server(opts \\ []) do
    capabilities = Keyword.get(opts, :capabilities, [:resources, :tools, :prompts])
    resources = Keyword.get(opts, :resources, [])
    tools = Keyword.get(opts, :tools, [])
    prompts = Keyword.get(opts, :prompts, [])
    
    # Create server
    server = TestServer.new(
      capabilities: capabilities,
      resources: resources,
      tools: tools,
      prompts: prompts
    )
    
    # Set up custom initialize handler to ensure proper format
    custom_init_handler = fn _server, message ->
      %{
        "jsonrpc" => "2.0",
        "id" => message["id"],
        "result" => %{
          "serverInfo" => %{
            "name" => "TestServer",
            "version" => "1.0.0"
          },
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{
            "resources" => (if :resources in capabilities, do: %{"subscribe" => true}, else: nil),
            "tools" => (if :tools in capabilities, do: true, else: nil),
            "prompts" => (if :prompts in capabilities, do: true, else: nil)
          }
        }
      }
    end
    
    # Set up ping handler for prompt responses
    ping_handler = fn _server, message ->
      %{
        "jsonrpc" => "2.0",
        "id" => message["id"],
        "result" => %{}
      }
    end
    
    # Set the custom handlers
    server = %{server | responses: Map.put(server.responses, "initialize", custom_init_handler)}
    %{server | responses: Map.put(server.responses, "ping", ping_handler)}
  end

  describe "client initialization" do
    test "initializes with minimal configuration" do
      # Create a test server
      server = create_test_server()
      
      # Start a transport connected to this server
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Initialize client with transport
      # Explicitly disable shell for tests
      {:ok, client} = Client.start_link(transport: transport, shell_type: :none)
      
      # Verify client is started
      assert Process.alive?(client)
      
      # Cleanup
      Client.stop(client)
    end

    test "handles initialization with client info" do
      # Create a test server
      server = create_test_server()
      
      # Start a transport connected to this server
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Initialize client with custom client info
      client_info = %{name: "TestClient", version: "1.0.0"}
      {:ok, client} = Client.start_link(
        transport: transport,
        client_info: client_info,
        shell_type: :none
      )
      
      # Verify client is started
      assert Process.alive?(client)
      
      # Cleanup
      Client.stop(client)
    end

    test "properly negotiates capabilities with server" do
      # Create a test server with specific capabilities
      server = create_test_server(capabilities: [:resources, :tools])
      
      # Start a transport connected to this server
      {:ok, transport} = TestTransport.start_link(server: server)
      
      # Initialize client with capabilities
      {:ok, client} = Client.start_link(
        transport: transport,
        capabilities: [:resources, :tools, :sampling],
        shell_type: :none
      )
      
      # Get negotiated server capabilities
      {:ok, capabilities} = Client.get_server_capabilities(client)
      
      # Verify negotiated capabilities exist
      assert Map.has_key?(capabilities, :resources)
      assert Map.has_key?(capabilities, :tools)
      
      # The test server is configured to have resources with subscribe capability
      assert get_in(capabilities, [:resources, :subscribe]) == true
      
      # Cleanup
      Client.stop(client)
    end
  end

  describe "basic operations" do
    setup do
      # Create test server and client for each test
      server = create_test_server()
      {:ok, transport} = TestTransport.start_link(server: server)
      {:ok, client} = Client.start_link(transport: transport, shell_type: :none)
      
      # Return client and server for use in tests
      %{client: client, server: server}
    end
    
    test "get_server_capabilities returns negotiated capabilities", %{client: client} do
      # Get server capabilities
      {:ok, capabilities} = Client.get_server_capabilities(client)
      
      # Verify capabilities structure
      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :resources)
      assert Map.has_key?(capabilities, :tools)
      assert Map.has_key?(capabilities, :prompts)
    end
    
    test "get_server_info returns server information", %{client: client} do
      # Get server info
      {:ok, server_info} = Client.get_server_info(client)
      
      # Verify server info structure
      assert is_map(server_info)
      assert Map.has_key?(server_info, :name)
      assert Map.has_key?(server_info, :version)
    end
    
    test "client stops cleanly", %{client: client} do
      # Stop the client
      assert :ok = Client.stop(client)
      
      # Verify process is no longer alive
      refute Process.alive?(client)
    end
  end
  
  describe "prompt operations" do
    setup do
      # Create a test server with prompt capabilities
      server = TestServer.new(
        capabilities: [:prompts],
        prompts: [
          %{
            name: "code_review",
            description: "A template for code review comments",
            parameters: %{
              type: "object",
              properties: %{
                code: %{
                  type: "string",
                  description: "The code to review"
                },
                language: %{
                  type: "string",
                  description: "The programming language"
                }
              },
              required: ["code"]
            }
          },
          %{
            name: "bug_report",
            description: "A template for reporting bugs",
            parameters: %{
              type: "object",
              properties: %{
                description: %{
                  type: "string",
                  description: "Description of the bug"
                },
                severity: %{
                  type: "string",
                  enum: ["low", "medium", "high"],
                  description: "Bug severity"
                }
              },
              required: ["description"]
            }
          }
        ]
      )
      
      # Configure the server to respond to prompt requests with custom handlers
      # For testing, we can just use the default handlers
      
      # Use the custom responses system instead of add_handler for backward compatibility
      prompts_list_handler = fn _server, message ->
        %{
          "jsonrpc" => "2.0",
          "result" => %{
            "prompts" => [
              %{
                "name" => "code_review",
                "description" => "A template for code review comments",
                "parameters" => %{
                  "type" => "object",
                  "properties" => %{
                    "code" => %{
                      "type" => "string",
                      "description" => "The code to review"
                    },
                    "language" => %{
                      "type" => "string",
                      "description" => "The programming language"
                    }
                  },
                  "required" => ["code"]
                }
              },
              %{
                "name" => "bug_report",
                "description" => "A template for reporting bugs",
                "parameters" => %{
                  "type" => "object",
                  "properties" => %{
                    "description" => %{
                      "type" => "string",
                      "description" => "Description of the bug"
                    },
                    "severity" => %{
                      "type" => "string",
                      "enum" => ["low", "medium", "high"],
                      "description" => "Bug severity"
                    }
                  },
                  "required" => ["description"]
                }
              }
            ],
            "next_cursor" => nil
          },
          "id" => message["id"]
        }
      end
      
      # Handler for prompts/get request
      prompts_get_handler = fn _server, message ->
        prompt_name = message["params"]["name"]
        # Use 'arguments' instead of 'args' for MCP 2025-03-26 compliance
        args = message["params"]["arguments"] || %{}
        
        case prompt_name do
          "code_review" ->
            code = args["code"] || "def example(): pass"
            language = args["language"] || "python"
            
            %{
              "jsonrpc" => "2.0",
              "result" => %{
                "description" => "A template for code review comments",
                "messages" => [
                  %{
                    "role" => "system",
                    "content" => "You are a code reviewer. Review the following #{language} code."
                  },
                  %{
                    "role" => "user",
                    "content" => "Please review this code: ```#{language}\n#{code}\n```"
                  }
                ]
              },
              "id" => message["id"]
            }
            
          "bug_report" ->
            description = args["description"] || "Unknown bug"
            severity = args["severity"] || "medium"
            
            %{
              "jsonrpc" => "2.0",
              "result" => %{
                "description" => "A template for reporting bugs",
                "messages" => [
                  %{
                    "role" => "system",
                    "content" => "You are reporting a bug with severity: #{severity}"
                  },
                  %{
                    "role" => "user",
                    "content" => "Bug description: #{description}"
                  }
                ]
              },
              "id" => message["id"]
            }
            
          _ ->
            %{
              "jsonrpc" => "2.0",
              "error" => %{
                "code" => -32602,
                "message" => "Prompt not found: #{prompt_name}"
              },
              "id" => message["id"]
            }
        end
      end
      
      # Update the server with our custom handlers
      server = %{server | responses: Map.put(server.responses, "prompts/list", prompts_list_handler)}
      server = %{server | responses: Map.put(server.responses, "prompts/get", prompts_get_handler)}
      
      # Start client with transport connected to test server
      {:ok, transport} = TestTransport.start_link(server: server)
      {:ok, client} = Client.start_link(transport: transport, shell_type: :none)
      
      %{client: client, server: server}
    end
    
    test "list_prompts returns available prompts", %{client: client} do
      # Test the prompts listing functionality
      {:ok, response} = Client.list_prompts(client)
      
      # The response might be a direct JSON-RPC result map with string keys
      result = 
        cond do
          # Response from transport_response handler
          is_map(response) && Map.has_key?(response, "prompts") -> response
          # Result from a normal Elixir atom-keyed map
          is_map(response) && Map.has_key?(response, :prompts) -> response
          # Full JSON-RPC response with string keys
          is_map(response) && Map.has_key?(response, "result") -> 
            response["result"]
          true -> response
        end
      
      # Verify result structure
      assert is_map(result)
      
      # Get prompts list, handling either string or atom keys
      prompts = result["prompts"] || result[:prompts]
      assert is_list(prompts)
      assert length(prompts) == 2
      
      # Check specific prompts
      code_review_prompt = Enum.find(prompts, fn p -> 
        (p["name"] || p[:name]) == "code_review" 
      end)
      assert code_review_prompt != nil
      assert (code_review_prompt["description"] || code_review_prompt[:description]) == "A template for code review comments"
      
      bug_report_prompt = Enum.find(prompts, fn p -> 
        (p["name"] || p[:name]) == "bug_report" 
      end)
      assert bug_report_prompt != nil
      assert (bug_report_prompt["description"] || bug_report_prompt[:description]) == "A template for reporting bugs"
    end
    
    test "get_prompt returns prompt with template parameters", %{client: client} do
      # Test getting a prompt with parameters
      prompt_name = "code_review"
      args = %{
        "code" => "function hello() { console.log('world'); }",
        "language" => "javascript"
      }
      
      {:ok, response} = Client.get_prompt(client, prompt_name, args)
      
      # Extract the result from various possible response formats
      result = 
        cond do
          # Direct result with atom keys
          is_map(response) && Map.has_key?(response, :description) -> response
          # Direct result with string keys
          is_map(response) && Map.has_key?(response, "description") -> response
          # Full JSON-RPC response
          is_map(response) && Map.has_key?(response, "result") -> 
            response["result"]
          true -> response
        end
      
      # Verify result structure
      assert is_map(result)
      
      # Verify description, handling either string or atom keys
      description = result["description"] || result[:description]
      assert description == "A template for code review comments"
      
      # Verify messages
      messages = result["messages"] || result[:messages]
      assert is_list(messages)
      assert length(messages) == 2
      
      # Verify message content contains the parameters
      user_message = Enum.find(messages, fn m -> 
        (m["role"] || m[:role]) == "user" 
      end)
      assert user_message != nil
      
      message_content = user_message["content"] || user_message[:content]
      assert String.contains?(message_content, "javascript")
      assert String.contains?(message_content, "function hello() { console.log('world'); }")
    end
    
    test "get_prompt handles errors for non-existent prompts", %{client: client} do
      # Test error handling for non-existent prompts
      prompt_name = "non_existent"
      
      # Try to get a non-existent prompt
      result = Client.get_prompt(client, prompt_name, %{})
      
      # Depending on the format, extract the error
      case result do
        {:error, error} ->
          # Verify error structure with atom keys
          assert is_map(error)
          assert error.code == -32602 || error["code"] == -32602 # invalid_params error code
          message = error.message || error["message"]
          assert String.contains?(message, "Prompt not found")
          
        {:ok, response} when is_map(response) ->
          # Check if this is a JSON-RPC response with an error field
          if Map.has_key?(response, "error") do
            error = response["error"]
            assert is_map(error)
            assert error["code"] == -32602 # invalid_params error code
            assert String.contains?(error["message"], "Prompt not found")
          else
            flunk("Expected response to have an error field but got: #{inspect(response)}")
          end
          
        _ ->
          flunk("Expected an error response but got: #{inspect(result)}")
      end
    end
  end
end