defmodule MCPEx.Transport.TestServer do
  @moduledoc """
  Test server implementation to pair with MCPEx.Transport.Test.

  This module simulates an MCP server for integration testing, allowing
  tests to verify client behavior without requiring an actual MCP server.
  
  ## Features
  
  * Simulate server responses and notifications
  * Control message timing and failures
  * Test specific scenarios and protocol flows
  * Verify client requests match expectations
  * Support all MCP protocol features (resources, tools, prompts, sampling)
  
  ## Usage
  
  ```elixir
  # Create a test server with capabilities
  server = MCPEx.Transport.TestServer.new(
    capabilities: [:resources, :tools]
  )
  
  # Start a test transport connected to this server
  {:ok, transport} = MCPEx.Transport.Test.start_link(server: server)
  
  # Trigger server events
  MCPEx.Transport.TestServer.send_notification(server, %{
    jsonrpc: "2.0",
    method: "notifications/resources/updated"
  })
  
  # Verify client messages
  assert MCPEx.Transport.TestServer.last_message(server).method == "initialize"
  ```
  """
  
  require Logger
  
  defstruct [
    # Connected clients
    clients: [],
    
    # Server capabilities and configuration
    capabilities: [],
    resources: [],
    tools: [],
    prompts: [],
    
    # Message handling
    received_messages: [],
    responses: %{},
    
    # Test control
    scenario: nil,
    delay: 0,
    error_rate: 0.0,
    
    # For testing/debugging
    log: [],
    
    # Recording for record & replay
    recording: nil
  ]
  
  @type client_ref :: reference()
  
  @type t :: %__MODULE__{
    clients: list({client_ref(), pid()}),
    capabilities: list(atom()),
    resources: list(map()),
    tools: list(map()),
    prompts: list(map()),
    received_messages: list(map()),
    responses: map(),
    scenario: atom() | nil,
    delay: non_neg_integer(),
    error_rate: float(),
    log: list(),
    recording: list() | nil
  }
  
  @doc """
  Creates a new test server instance.
  
  ## Options
  
  * `:capabilities` - List of server capabilities (default: [])
  * `:scenario` - Name of the test scenario to run (default: nil)
  * `:delay` - Artificial delay in milliseconds for responses (default: 0)
  * `:error_rate` - Probability of simulated errors (0.0-1.0, default: 0.0)
  * `:resources` - Initial resources to serve (default: [])
  * `:tools` - Initial tools to serve (default: [])
  * `:prompts` - Initial prompts to serve (default: [])
  
  ## Returns
  
  * A new TestServer struct
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    recording_mode = Keyword.get(options, :record_mode, false)
    
    %__MODULE__{
      clients: [],
      capabilities: Keyword.get(options, :capabilities, []),
      resources: Keyword.get(options, :resources, []),
      tools: Keyword.get(options, :tools, []),
      prompts: Keyword.get(options, :prompts, []),
      scenario: Keyword.get(options, :scenario),
      delay: Keyword.get(options, :delay, 0),
      error_rate: Keyword.get(options, :error_rate, 0.0),
      received_messages: [],
      responses: build_default_responses(),
      log: [],
      recording: if(recording_mode, do: [], else: Keyword.get(options, :recording))
    }
  end
  
  # Build default responses for common requests
  defp build_default_responses do
    %{
      "initialize" => fn server, message ->
        %{
          "jsonrpc" => "2.0",
          "result" => %{
            "serverInfo" => %{
              "name" => "TestServer",
              "version" => "1.0.0"
            },
            "capabilities" => capabilities_to_map(server.capabilities)
          },
          "id" => message["id"]
        }
      end,
      
      "resources/list" => fn server, message ->
        %{
          "jsonrpc" => "2.0",
          "result" => %{
            "resources" => server.resources,
            "next_cursor" => nil
          },
          "id" => message["id"]
        }
      end,
      
      "resources/read" => fn server, message ->
        uri = message["params"]["uri"]
        resource = Enum.find(server.resources, fn r -> r["uri"] == uri end)
        
        if resource do
          %{
            "jsonrpc" => "2.0",
            "result" => %{
              "contents" => [
                %{
                  "type" => "text",
                  "text" => resource["content"] || "Sample content"
                }
              ]
            },
            "id" => message["id"]
          }
        else
          %{
            "jsonrpc" => "2.0",
            "error" => %{
              "code" => -32602,
              "message" => "Resource not found: #{uri}"
            },
            "id" => message["id"]
          }
        end
      end,
      
      "tools/list" => fn server, message ->
        %{
          "jsonrpc" => "2.0",
          "result" => %{
            "tools" => server.tools,
            "next_cursor" => nil
          },
          "id" => message["id"]
        }
      end,
      
      "tools/call" => fn server, message ->
        tool_name = message["params"]["name"]
        tool = Enum.find(server.tools, fn t -> t["name"] == tool_name end)
        
        if tool do
          tool_handler = tool["handler"]
          args = message["params"]["args"]
          
          if is_function(tool_handler) do
            result = tool_handler.(args)
            
            %{
              "jsonrpc" => "2.0",
              "result" => %{
                "content" => [
                  %{
                    "type" => "text",
                    "text" => inspect(result)
                  }
                ],
                "is_error" => false
              },
              "id" => message["id"]
            }
          else
            # Default simple response
            %{
              "jsonrpc" => "2.0",
              "result" => %{
                "content" => [
                  %{
                    "type" => "text",
                    "text" => "Tool #{tool_name} executed with args: #{inspect(message["params"]["args"])}"
                  }
                ],
                "is_error" => false
              },
              "id" => message["id"]
            }
          end
        else
          %{
            "jsonrpc" => "2.0",
            "error" => %{
              "code" => -32602,
              "message" => "Tool not found: #{tool_name}"
            },
            "id" => message["id"]
          }
        end
      end,
      
      "prompts/list" => fn server, message ->
        %{
          "jsonrpc" => "2.0",
          "result" => %{
            "prompts" => server.prompts,
            "next_cursor" => nil
          },
          "id" => message["id"]
        }
      end,
      
      "prompts/get" => fn server, message ->
        prompt_name = message["params"]["name"]
        prompt = Enum.find(server.prompts, fn p -> p["name"] == prompt_name end)
        
        if prompt do
          # Use 'arguments' parameter instead of 'args' for MCP 2025-03-26 compliance
          args = message["params"]["arguments"] || %{}
          
          %{
            "jsonrpc" => "2.0",
            "result" => %{
              "description" => prompt["description"] || "A prompt template",
              "messages" => [
                %{
                  "role" => "system",
                  "content" => prompt["system_message"] || "You are a helpful assistant."
                },
                %{
                  "role" => "user",
                  "content" => "Please review this code: ```#{args["language"] || "python"}\n#{args["code"] || "def example(): pass"}\n```"
                }
              ]
            },
            "id" => message["id"]
          }
        else
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
    }
  end
  
  # Convert capabilities list to the right format for initialize response
  defp capabilities_to_map(capabilities) when is_list(capabilities) do
    Enum.reduce(capabilities, %{}, fn capability, acc ->
      case capability do
        :resources ->
          Map.put(acc, "resources", %{"subscribe" => true})
        :tools ->
          Map.put(acc, "tools", true)
        :prompts ->
          Map.put(acc, "prompts", true)
        :sampling ->
          Map.put(acc, "sampling", true)
        :roots ->
          Map.put(acc, "roots", true)
        capability when is_atom(capability) ->
          Map.put(acc, Atom.to_string(capability), true)
        _ ->
          acc # Skip non-atom values
      end
    end)
  end
  
  # Handle map-style capabilities for backward compatibility
  defp capabilities_to_map(capabilities) when is_map(capabilities) do
    # Convert map capabilities to string keys
    Enum.reduce(Map.to_list(capabilities), %{}, fn {key, value}, acc ->
      key_str = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      
      # Handle different value types
      value_converted = case value do
        true -> true
        v when is_map(v) -> 
          # Convert nested maps like %{listChanged: true} to %{"listChanged" => true}
          Enum.reduce(Map.to_list(v), %{}, fn {k, v}, inner_acc ->
            k_str = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
            Map.put(inner_acc, k_str, v)
          end)
        _ -> value
      end
      
      Map.put(acc, key_str, value_converted)
    end)
  end
  
  @doc """
  Registers a client with the server.
  
  ## Parameters
  
  * `server` - The server struct
  * `client_pid` - PID of the client transport process
  
  ## Returns
  
  * `{ref, updated_server}` - The client reference and updated server
  """
  @spec register_client(t(), pid()) :: {client_ref(), t()}
  def register_client(server, client_pid) do
    ref = make_ref()
    updated_server = %{server | clients: [{ref, client_pid} | server.clients]}
    
    # Log registration
    updated_server = add_log(updated_server, "Client registered: #{inspect(client_pid)}")
    
    # If a scenario is configured, handle it
    updated_server = maybe_start_scenario(updated_server, ref)
    
    {ref, updated_server}
  end
  
  @doc """
  Unregisters a client from the server.
  
  ## Parameters
  
  * `server` - The server struct
  * `client_ref` - Reference for the client to unregister
  
  ## Returns
  
  * Updated server struct
  """
  @spec unregister_client(t(), client_ref()) :: t()
  def unregister_client(server, client_ref) do
    updated_clients = Enum.reject(server.clients, fn {ref, _} -> ref == client_ref end)
    updated_server = %{server | clients: updated_clients}
    add_log(updated_server, "Client unregistered: #{inspect(client_ref)}")
  end
  
  @doc """
  Processes a message from a client.
  
  ## Parameters
  
  * `server` - The server struct
  * `client_ref` - Reference for the client sending the message
  * `message` - The message received from the client
  
  ## Returns
  
  * `{response, updated_server}` - Response to send back and updated server
  """
  @spec process_message(t(), client_ref(), map() | String.t()) :: {map() | {:error, term()}, t()}
  def process_message(server, client_ref, message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        process_message(server, client_ref, decoded)
      {:error, reason} ->
        error_response = %{
          "jsonrpc" => "2.0",
          "error" => %{
            "code" => -32700,
            "message" => "Parse error: #{inspect(reason)}"
          },
          "id" => nil
        }
        {error_response, server}
    end
  end
  
  def process_message(server, client_ref, message) when is_map(message) do
    # Add to received messages
    updated_server = %{server | received_messages: [message | server.received_messages]}
    updated_server = add_log(updated_server, "Received message: #{inspect(message)}")
    
    # If in recording mode, add to the recording
    updated_server = if updated_server.recording != nil and is_list(updated_server.recording) do
      recording_entry = %{
        type: :request,
        message: message,
        timestamp: :os.system_time(:millisecond)
      }
      %{updated_server | recording: [recording_entry | updated_server.recording]}
    else
      updated_server
    end
    
    # Check if we should simulate an error
    if should_return_error?(updated_server) do
      error_response = %{
        "jsonrpc" => "2.0",
        "error" => %{
          "code" => -32000,
          "message" => "Simulated error"
        },
        "id" => message["id"]
      }
      
      # If in recording mode, record the response
      final_server = if updated_server.recording != nil and is_list(updated_server.recording) do
        recording_entry = %{
          type: :response,
          message: error_response,
          request_id: message["id"],
          timestamp: :os.system_time(:millisecond)
        }
        %{updated_server | recording: [recording_entry | updated_server.recording]}
      else
        updated_server
      end
      
      {error_response, final_server}
    else
      # Generate response based on the method
      method = message["method"]
      
      # Check if we have a handler for this method
      if Map.has_key?(updated_server.responses, method) do
        response_fn = updated_server.responses[method]
        response = response_fn.(updated_server, message)
        
        # Add artificial delay if configured
        if updated_server.delay > 0 do
          Process.sleep(updated_server.delay)
        end
        
        # Process any scenario-specific behavior
        updated_server = process_scenario(updated_server, client_ref, message, response)
        
        # If in recording mode, record the response
        final_server = if updated_server.recording != nil and is_list(updated_server.recording) do
          recording_entry = %{
            type: :response,
            message: response,
            request_id: message["id"],
            timestamp: :os.system_time(:millisecond)
          }
          %{updated_server | recording: [recording_entry | updated_server.recording]}
        else
          updated_server
        end
        
        {response, final_server}
      else
        # Method not found
        error_response = %{
          "jsonrpc" => "2.0",
          "error" => %{
            "code" => -32601,
            "message" => "Method not found: #{method}"
          },
          "id" => message["id"]
        }
        
        # If in recording mode, record the response
        final_server = if updated_server.recording != nil and is_list(updated_server.recording) do
          recording_entry = %{
            type: :response,
            message: error_response,
            request_id: message["id"],
            timestamp: :os.system_time(:millisecond)
          }
          %{updated_server | recording: [recording_entry | updated_server.recording]}
        else
          updated_server
        end
        
        {error_response, final_server}
      end
    end
  end
  
  # Check if we should simulate an error based on error_rate
  defp should_return_error?(server) do
    if server.error_rate > 0 do
      :rand.uniform() < server.error_rate
    else
      false
    end
  end
  
  @doc """
  Sends a notification message to a client.
  
  ## Parameters
  
  * `server` - The server struct
  * `notification` - The notification message to send
  * `client_ref` - Optional client reference (sends to all if nil)
  
  ## Returns
  
  * Updated server struct
  """
  @spec send_notification(t(), map(), client_ref() | nil) :: t()
  def send_notification(server, notification, client_ref \\ nil) do
    updated_server = add_log(server, "Sending notification: #{inspect(notification)}")
    
    # If in recording mode, add to the recording
    updated_server = if updated_server.recording != nil and is_list(updated_server.recording) do
      recording_entry = %{
        type: :notification,
        message: notification,
        client_ref: client_ref,
        timestamp: :os.system_time(:millisecond)
      }
      %{updated_server | recording: [recording_entry | updated_server.recording]}
    else
      updated_server
    end
    
    if client_ref do
      # Send to specific client
      client = Enum.find(updated_server.clients, fn {ref, _} -> ref == client_ref end)
      if client do
        {_, pid} = client
        send(pid, {:test_server_notification, notification})
      end
    else
      # Send to all clients
      Enum.each(updated_server.clients, fn {_, pid} ->
        send(pid, {:test_server_notification, notification})
      end)
    end
    
    updated_server
  end
  
  @doc """
  Triggers a sampling request.
  
  ## Parameters
  
  * `server` - The server struct
  * `options` - Options for the sampling request
  * `client_ref` - Optional client reference (first client if nil)
  
  ## Returns
  
  * Updated server struct
  """
  @spec request_sampling(t(), keyword(), client_ref() | nil) :: t()
  def request_sampling(server, options, client_ref \\ nil) do
    messages = Keyword.get(options, :messages, [%{"role" => "user", "content" => "Test message"}])
    model_preferences = Keyword.get(options, :model_preferences, %{"intelligence_priority" => 0.5})
    id = Keyword.get(options, :id, System.unique_integer([:positive]))
    
    sampling_request = %{
      "jsonrpc" => "2.0",
      "method" => "sampling/createMessage",
      "params" => %{
        "messages" => messages,
        "model_preferences" => model_preferences
      },
      "id" => id
    }
    
    # Determine target client
    target_client_ref = if client_ref do
      client_ref
    else
      case server.clients do
        [{ref, _} | _] -> ref
        _ -> nil
      end
    end
    
    if target_client_ref do
      send_notification(server, sampling_request, target_client_ref)
    else
      add_log(server, "No clients available for sampling request")
    end
  end
  
  @doc """
  Adds a resource to the server.
  
  ## Parameters
  
  * `server` - The server struct
  * `resource` - The resource to add
  
  ## Returns
  
  * Updated server struct
  """
  @spec add_resource(t(), map() | keyword()) :: t()
  def add_resource(server, resource) when is_list(resource) do
    add_resource(server, Map.new(resource))
  end
  
  def add_resource(server, resource) when is_map(resource) do
    # Ensure URI is present
    unless Map.has_key?(resource, "uri") do
      raise ArgumentError, "Resource must have a 'uri' field"
    end
    
    # Add to resources list
    updated_resources = [resource | server.resources]
    updated_server = %{server | resources: updated_resources}
    
    # Notify clients if we have any
    if server.clients != [] do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/resources/list_changed",
        "params" => %{}
      }
      send_notification(updated_server, notification)
    else
      updated_server
    end
  end
  
  @doc """
  Adds a tool to the server.
  
  ## Parameters
  
  * `server` - The server struct
  * `tool` - The tool to add
  
  ## Returns
  
  * Updated server struct
  """
  @spec add_tool(t(), map() | keyword()) :: t()
  def add_tool(server, tool) when is_list(tool) do
    add_tool(server, Map.new(tool))
  end
  
  def add_tool(server, tool) when is_map(tool) do
    # Ensure name is present
    unless Map.has_key?(tool, "name") do
      raise ArgumentError, "Tool must have a 'name' field"
    end
    
    # Add to tools list
    updated_tools = [tool | server.tools]
    updated_server = %{server | tools: updated_tools}
    
    # Notify clients if we have any
    if server.clients != [] do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/tools/list_changed",
        "params" => %{}
      }
      send_notification(updated_server, notification)
    else
      updated_server
    end
  end
  
  @doc """
  Adds a prompt to the server.
  
  ## Parameters
  
  * `server` - The server struct
  * `prompt` - The prompt to add
  
  ## Returns
  
  * Updated server struct
  """
  @spec add_prompt(t(), map() | keyword()) :: t()
  def add_prompt(server, prompt) when is_list(prompt) do
    add_prompt(server, Map.new(prompt))
  end
  
  def add_prompt(server, prompt) when is_map(prompt) do
    # Ensure name is present
    unless Map.has_key?(prompt, "name") do
      raise ArgumentError, "Prompt must have a 'name' field"
    end
    
    # Add to prompts list
    updated_prompts = [prompt | server.prompts]
    updated_server = %{server | prompts: updated_prompts}
    
    # Notify clients if we have any
    if server.clients != [] do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/prompts/list_changed",
        "params" => %{}
      }
      send_notification(updated_server, notification)
    else
      updated_server
    end
  end
  
  @doc """
  Checks if the server received a message matching the given criteria.
  
  ## Parameters
  
  * `server` - The server struct
  * `criteria` - Criteria to match (method, id, etc.)
  
  ## Returns
  
  * `true` or `false`
  """
  @spec received_message?(t(), keyword()) :: boolean()
  def received_message?(server, criteria) do
    method = Keyword.get(criteria, :method)
    id = Keyword.get(criteria, :id)
    
    Enum.any?(server.received_messages, fn message ->
      matches = true
      
      matches = if method && matches do
        message["method"] == method
      else
        matches
      end
      
      matches = if id && matches do
        message["id"] == id
      else
        matches
      end
      
      matches
    end)
  end
  
  @doc """
  Gets the last message received by the server.
  
  ## Parameters
  
  * `server` - The server struct
  
  ## Returns
  
  * The last message or nil if none
  """
  @spec last_message(t()) :: map() | nil
  def last_message(server) do
    List.first(server.received_messages)
  end
  
  @doc """
  Gets all messages received by the server.
  
  ## Parameters
  
  * `server` - The server struct
  
  ## Returns
  
  * List of messages in reverse chronological order
  """
  @spec received_messages(t()) :: [map()]
  def received_messages(server) do
    server.received_messages
  end
  
  @doc """
  Sets a custom response handler for a specific method.
  
  ## Parameters
  
  * `server` - The server struct
  * `method` - The method to handle
  * `handler` - Function that takes (server, message) and returns response
  
  ## Returns
  
  * Updated server struct
  """
  @spec set_response_handler(t(), String.t(), function()) :: t()
  def set_response_handler(server, method, handler) when is_function(handler, 2) do
    updated_responses = Map.put(server.responses, method, handler)
    %{server | responses: updated_responses}
  end
  
  # Private helpers
  
  # Add a log entry
  defp add_log(server, entry) do
    timestamp = :os.system_time(:millisecond)
    log_entry = {timestamp, entry}
    %{server | log: [log_entry | server.log]}
  end
  
  # Start scenario if one is configured
  defp maybe_start_scenario(server, client_ref) do
    case server.scenario do
      :resource_changes ->
        # Schedule resource changes after a delay
        spawn(fn ->
          Process.sleep(100)
          resource = %{"uri" => "file:///test.txt", "content" => "Initial content"}
          updated_server = add_resource(server, resource)
          
          Process.sleep(100)
          notification = %{
            "jsonrpc" => "2.0",
            "method" => "notifications/resources/updated",
            "params" => %{"uri" => "file:///test.txt"}
          }
          send_notification(updated_server, notification)
        end)
        server
        
      :capability_update ->
        # Schedule a capability update after initialization
        spawn(fn ->
          Process.sleep(200)
          notification = %{
            "jsonrpc" => "2.0",
            "method" => "notifications/capabilities/changed",
            "params" => %{
              "additions" => ["sampling"],
              "removals" => []
            }
          }
          send_notification(server, notification, client_ref)
        end)
        server
        
      :connection_error ->
        # Schedule a connection error after a delay
        spawn(fn ->
          Process.sleep(300)
          {_, pid} = Enum.find(server.clients, fn {ref, _} -> ref == client_ref end)
          send(pid, {:test_server_error, "Simulated connection error"})
        end)
        server
        
      _ ->
        # No scenario or unknown scenario
        server
    end
  end
  
  # Process scenario-specific behavior after a message
  defp process_scenario(server, client_ref, message, _response) do
    case server.scenario do
      :connection_error_after_n_messages ->
        # Check if we've reached the message count threshold
        if length(server.received_messages) >= 5 do
          # Find the client and send an error
          case Enum.find(server.clients, fn {ref, _} -> ref == client_ref end) do
            {_, pid} ->
              send(pid, {:test_server_error, "Simulated connection error after #{length(server.received_messages)} messages"})
            nil ->
              nil
          end
        end
        server
        
      :incremental_capabilities ->
        # If this was an initialize request, schedule adding capabilities gradually
        if message["method"] == "initialize" do
          # Schedule adding capabilities over time
          spawn(fn ->
            # Add tools after a delay
            Process.sleep(100)
            notification = %{
              "jsonrpc" => "2.0",
              "method" => "notifications/capabilities/changed",
              "params" => %{
                "additions" => ["tools"],
                "removals" => []
              }
            }
            send_notification(server, notification)
            
            # Add resources after another delay
            Process.sleep(100)
            notification = %{
              "jsonrpc" => "2.0",
              "method" => "notifications/capabilities/changed",
              "params" => %{
                "additions" => ["resources"],
                "removals" => []
              }
            }
            send_notification(server, notification)
          end)
        end
        server
        
      _ ->
        # No scenario or unknown scenario
        server
    end
  end
  
  @doc """
  Gets the current recording for later replay.

  ## Parameters

  * `server` - The server struct

  ## Returns

  * The recording data or nil if not in recording mode
  """
  @spec get_recording(t()) :: list() | nil
  def get_recording(server) do
    case server.recording do
      nil -> nil
      [] -> []
      recording when is_list(recording) -> Enum.reverse(recording)
    end
  end
  
  @doc """
  Adds a custom handler for a specific method or response.
  
  ## Parameters
  
  * `server` - The server struct
  * `method` - The method name to handle
  * `handler_fn` - A function that takes the params and returns the result or an error
  
  ## Returns
  
  * Updated server struct
  """
  @spec add_handler(t(), String.t(), function()) :: t()
  def add_handler(server, method, handler_fn) when is_function(handler_fn, 1) do
    # Create a wrapper that adapts the handler_fn to the expected signature (server, message) -> response
    wrapper = fn _server, message ->
      params = Map.get(message, "params", %{})
      
      # Call the handler and format the response
      try do
        result = handler_fn.(params)
        case result do
          {:error, code, message} ->
            # Handle explicit error return
            %{
              "jsonrpc" => "2.0",
              "error" => %{
                "code" => code,
                "message" => message
              },
              "id" => message["id"]
            }
          _ ->
            # Normal result
            %{
              "jsonrpc" => "2.0",
              "result" => result,
              "id" => message["id"]
            }
        end
      rescue
        e ->
          # Exception caught from handler
          %{
            "jsonrpc" => "2.0",
            "error" => %{
              "code" => -32603,
              "message" => "Internal error in handler: #{inspect(e)}"
            },
            "id" => message["id"]
          }
      end
    end
    
    # Update the responses map with the new handler
    updated_responses = Map.put(server.responses, method, wrapper)
    %{server | responses: updated_responses}
  end
  
  @doc """
  Creates a standard error response for use in handlers.
  
  ## Parameters
  
  * `error_type` - The type of error (atom like :invalid_params, :parse_error)
  * `message` - The error message
  * `data` - Optional additional data about the error
  
  ## Returns
  
  * `{:error, code, message}` - Error tuple that can be returned from handlers
  """
  @spec error(atom(), String.t(), map() | nil) :: {:error, integer(), String.t()}
  def error(error_type, message, data \\ nil) do
    code = case error_type do
      :parse_error -> -32700
      :invalid_request -> -32600
      :method_not_found -> -32601
      :invalid_params -> -32602
      :internal_error -> -32603
      # Server errors
      :server_error -> -32000
      # Application errors
      :application_error -> -32500
      # MCP-specific errors
      :resource_not_found -> 10001
      :tool_not_found -> 10002
      :prompt_not_found -> 10003
      :capability_not_supported -> 10004
      _ -> -32000 # Default to server error
    end
    
    # Construct the error object
    error_message = if is_nil(data) do
      message
    else
      "#{message} #{inspect(data)}"
    end
    
    {:error, code, error_message}
  end
end