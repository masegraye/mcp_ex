defmodule MCPEx.Transport.Stdio do
  @moduledoc """
  Implementation of the MCP transport over standard I/O.

  This transport spawns an external process and communicates with it over
  standard input/output pipes. It handles encoding/decoding of messages
  and manages the lifecycle of the external process.
  """

  use GenServer
  require Logger
  import Bitwise

  @doc """
  Starts a new stdio transport as a linked process.

  ## Options

  * `:command` - The command to execute (required)
  * `:args` - List of command arguments (default: [])
  * `:cd` - Working directory for the command (default: current directory)
  * `:env` - Environment variables for the command (default: current environment)

  ## Returns

  * `{:ok, pid}` - The transport was started successfully
  * `{:error, reason}` - Failed to start the transport
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end
  
  @doc """
  Gets any captured stderr output that was buffered.
  This is useful for diagnosing initialization failures.
  """
  @spec get_stderr_buffer(pid()) :: String.t() | nil
  def get_stderr_buffer(pid) do
    try do
      GenServer.call(pid, :get_stderr_buffer)
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end
  
  @doc """
  Stops buffering stderr. Called by the client after initialization is complete.
  """
  @spec stop_buffering_stderr(pid()) :: :ok
  def stop_buffering_stderr(pid) do
    try do
      GenServer.cast(pid, :stop_buffering_stderr)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    args = Keyword.get(options, :args, [])
    cd = Keyword.get(options, :cd, File.cwd!())
    env = Keyword.get(options, :env, [])
    use_wrapper = Keyword.get(options, :use_wrapper, true)
    use_shell_env = Keyword.get(options, :use_shell_env, false)
    _command_with_path = Keyword.get(options, :command_with_path)
    needs_shell_delay = Keyword.get(options, :needs_shell_delay, false)

    # Log debug info
    Logger.debug("Stdio transport starting with command: #{command}")
    Logger.debug("Args: #{inspect(args)}")

    # Basic port options that apply in all cases
    port_options = [
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      {:cd, cd},
      {:env, env}
    ]
    
    # Initialize with buffer and stderr buffering enabled
    init_state = %{
      buffer: "",          # Normal data buffer
      stderr_buffer: "",   # Buffer for stderr during initialization
      buffer_stderr: true  # By default, buffer stderr until initialization completes
    }

    try do
      # Check if we should use CommandUtils for enhanced shell environment
      if use_shell_env && Code.ensure_loaded?(MCPEx.Utils.CommandUtils) do
        Logger.debug("Using direct Port.open approach for shell-wrapped command")
        
        # For shell-wrapped commands, we don't need to add an additional shell layer
        # Instead, open the port directly with the given command and args
        Logger.debug("Attempting to open port with executable: #{command}")
        Logger.debug("Full port options: #{inspect(port_options ++ [{:args, Enum.map(args, &String.to_charlist/1)}])}")
        
        Logger.debug("About to try opening port")
        port = try do
          # Verify the command path exists
          if !File.exists?(command) do
            Logger.error("Command path does not exist: #{command}")
            nil
          else
            # Check if the file is executable
            case File.stat(command) do
              {:ok, %{mode: mode}} ->
                if (mode &&& 0o111) != 0 do
                  # Executable bit is set, try to open the port
                  Logger.debug("Command exists and is executable. Opening port...")
                  
                  # Following the approach that works in CommandUtils.execute_through_port
                  
                  # Convert to charlist for exec path explicitly
                  exec_path = String.to_charlist(command)
                  
                  # Basic port options - keep it simple and identical to CommandUtils
                  port_options = [:binary, :exit_status, :use_stdio]
                  
                  # Add cd option if needed (must be charlist)
                  port_options = if cd != nil && cd != "", do: port_options ++ [{:cd, cd}], else: port_options
                  
                  # Add env option if needed - MUST BE CHARLIST TUPLES
                  env_list = case env do
                    env when is_list(env) -> 
                      # Convert each element to ensure it's a charlist tuple
                      Enum.map(env, fn 
                        {k, v} when is_binary(k) and is_binary(v) -> {String.to_charlist(k), String.to_charlist(v)}
                        {k, v} when is_binary(k) -> {String.to_charlist(k), to_charlist(v)}
                        {k, v} when is_binary(v) -> {to_charlist(k), String.to_charlist(v)}
                        entry -> entry # Keep as is if we can't convert
                      end)
                    
                    env when is_map(env) -> 
                      # Convert map to list of tuples with charlists
                      env |> Enum.map(fn {k, v} -> 
                        {String.to_charlist("#{k}"), String.to_charlist("#{v}")}
                      end)
                    
                    _ -> []  # Default to empty list
                  end
                  
                  # Debug print the env list
                  Logger.debug("ENV LIST for port: #{inspect(env_list)}")
                  
                  # Only add env if not empty
                  port_options = if length(env_list) > 0, do: port_options ++ [{:env, env_list}], else: port_options
                  
                  # Convert args to charlists
                  char_args = Enum.map(args, fn arg -> 
                    cond do
                      is_binary(arg) -> String.to_charlist(arg)
                      is_list(arg) and is_integer(hd(arg)) -> arg  # Already a charlist
                      true -> to_charlist("#{arg}")  # Convert anything else
                    end
                  end)
                  
                  # Add args option
                  port_options = port_options ++ [{:args, char_args}]
                  
                  Logger.debug("FINAL port_options = #{inspect(port_options)}")
                  
                  # Open port with simplified options
                  port_result = Port.open({:spawn_executable, exec_path}, port_options)
                  
                  # Get the OS PID from the port
                  os_pid =
                    case Port.info(port_result, :os_pid) do
                      {:os_pid, pid} when is_integer(pid) -> "#{pid}"
                      _ -> "unknown"
                    end
                    
                  Logger.debug("Port opened successfully with PID: #{os_pid}")
                  port_result
                else
                  Logger.error("Command exists but is not executable: #{command} (mode: #{inspect(mode)})")
                  nil
                end
              {:error, reason} ->
                Logger.error("Failed to stat command: #{command}, reason: #{inspect(reason)}")
                nil
            end
          end
        rescue
          error ->
            Logger.error("Error opening port: #{inspect(error)}")
            nil
        catch
          kind, reason ->
            Logger.error("Caught #{kind} while opening port: #{inspect(reason)}")
            nil
        end
        
        Logger.debug("After try block, port value is: #{inspect(port)}")
        
        # Check if we got a valid port
        if is_nil(port) do
          Logger.error("Failed to open port for command: #{command}")
          {:error, "Failed to open port for command: #{command}"}
        else          
          # Get the OS PID from the port
          os_pid =
            case Port.info(port, :os_pid) do
              {:os_pid, pid} when is_integer(pid) -> "#{pid}"
              _ -> "unknown"
            end
          
          # Store the needs_shell_delay value in the process dictionary
          # so the client can check it when initializing
          if needs_shell_delay do
            Logger.debug("Setting needs_shell_delay in process dictionary")
            Process.put(:"$needs_shell_delay", true)
          end
          
          Logger.debug("Started shell-wrapped command directly with PID: #{os_pid}")
          # No need to create an unused variable
          
          # Port is open and we have the OS PID
          Logger.debug("Started command through shell with PID: #{os_pid}")
          # Initialize with our full state including stderr buffering
          # CRITICAL: port MUST be included in the state for Port.command to work
          # Make sure we're using actual port (not just the :ok result from try)
          if is_port(port) do
            # Set up monitoring for the port
            port_ref = Port.monitor(port)
            Logger.debug("Set up port monitoring with ref: #{inspect(port_ref)}")
            
            final_state = init_state
              |> Map.put(:port, port)
              |> Map.put(:port_ref, port_ref)
              
            Logger.debug("Returning state with port: #{inspect(Map.get(final_state, :port))}")
            {:ok, final_state}
          else
            Logger.error("Port variable is not a valid port: #{inspect(port)}")
            {:error, "Failed to get a valid port object"}
          end
        end
      else
        # Fall back to standard approach if CommandUtils is not available
        Logger.debug("Using standard Port.open approach (CommandUtils not available)")
        
        case System.find_executable(command) do
          nil ->
            # Return as a normal tuple for testing purposes
            {:error, "Command not found: #{command}"}

          command_path ->
            # If we should use the wrapper, set it up
            {exec_path, exec_args} = 
              if use_wrapper do
                wrapper_path = Application.app_dir(:mcp_ex, "priv/scripts/wrapper.sh")
                final_path = wrapper_path
                final_args = [command_path | args]
                
                # Log the full command with wrapper
                Logger.debug("Using wrapper script to run command")
                Logger.debug("Wrapper path: #{wrapper_path}")
                Logger.debug("Final command: #{wrapper_path} #{Enum.join([command_path | args], " ")}")
                
                {final_path, final_args}
              else
                Logger.debug("Running command directly (no wrapper)")
                Logger.debug("Final command: #{command_path} #{Enum.join(args, " ")}")
                
                {command_path, args}
              end

            # Add args to port options
            port_options = Keyword.put(port_options, :args, exec_args)

            # Now open the port with the appropriate path and arguments
            Logger.debug("Opening port with executable: #{exec_path}")
            Logger.debug("Port args: #{inspect(exec_args)}")
            port = Port.open({:spawn_executable, exec_path}, port_options)
            # Initialize with our full state including stderr buffering
            # CRITICAL: port MUST be included in the state for Port.command to work
            
            # Set up monitoring for the port
            port_ref = Port.monitor(port)
            Logger.debug("Set up port monitoring with ref: #{inspect(port_ref)}")
            
            final_state = init_state
              |> Map.put(:port, port)
              |> Map.put(:port_ref, port_ref)
              
            Logger.debug("Returning state with port: #{inspect(Map.get(final_state, :port))}")
            {:ok, final_state}
        end
      end
    catch
      _kind, reason ->
        {:error, "Error starting process: #{inspect(reason)}"}
    end
  end

  @doc """
  Sends a message to the process.

  ## Parameters

  * `message` - The message to send

  ## Returns

  * `:ok` - The message was sent successfully
  * `{:error, reason}` - Failed to send the message
  """
  @spec send_message(pid(), String.t()) :: :ok | {:error, term()}
  def send_message(pid, message) do
    GenServer.call(pid, {:send, message})
  end

  @doc """
  Closes the transport connection.

  ## Returns

  * `:ok` - The connection was closed successfully
  """
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.call(pid, :close)
  end

  @impl true
  def handle_call({:send, message}, _from, state) do
    # Add a newline terminator to the message
    message_with_newline = message <> "\n"
    
    # Send the message to the port
    result = Port.command(state.port, message_with_newline)
    
    if result do
      {:reply, :ok, state}
    else
      {:reply, {:error, "Failed to send message"}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stderr_buffer, _from, state) do
    # Return the current stderr buffer
    {:reply, state.stderr_buffer, state}
  end

  @impl true
  def handle_call(:close, _from, state) do
    try do
      if state.port do
        # First check if the port is still alive/valid
        port_info = Port.info(state.port)
        
        if port_info != nil do
          # Send close signal to port directly - ignore errors
          try do
            send(state.port, {self(), :close})
          rescue
            _ -> :ok
          catch
            _, _ -> :ok
          end
          
          # Also use Port.close to ensure it's closed - ignore errors
          try do
            Port.close(state.port)
          rescue
            _ -> :ok
          catch
            _, _ -> :ok
          end
        end
      end
    rescue
      error -> 
        # Log the error and continue
        Logger.error("Error closing port: #{inspect(error)}")
    catch
      kind, reason -> 
        # Log any errors and continue
        Logger.error("Error closing port: #{inspect(kind)}, #{inspect(reason)}")
    end
    
    # Always return OK
    {:reply, :ok, %{state | port: nil}}
  end

  @impl true
  def handle_cast(:stop_buffering_stderr, state) do
    # Stop buffering stderr by setting buffer_stderr to false
    {:noreply, Map.put(state, :buffer_stderr, false)}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Verify port is still valid in our state
    Logger.debug("Received data message, state port value: #{inspect(Map.get(state, :port))}")
    Logger.debug("Port is a valid port? #{is_port(Map.get(state, :port))}")
    cond do
      String.starts_with?(data, "[STDERR] ") ->
        # Handle stderr output
        stderr_line = String.slice(data, 9, String.length(data))
        Logger.debug("STDERR: #{stderr_line}")
        
        # Buffer stderr if buffering is enabled (default during initialization)
        stderr_buffer = 
          if Map.get(state, :buffer_stderr, true) do
            state.stderr_buffer <> stderr_line <> "\n"
          else
            state.stderr_buffer
          end
          
        # Check for our special error marker
        if String.contains?(stderr_line, "##MCP_ERROR##") do
          Logger.warning("Detected command failure marker: #{stderr_line}")
          
          # Extract exit code if possible
          exit_code = 
            case Regex.run(~r/exited with status: (\d+)/, stderr_line) do
              [_, code] -> String.to_integer(code)
              _ -> 1 # Default exit code if we can't parse it
            end
          
          # Create a detailed error message that includes the actual stderr output
          error_message = "Command failed with exit code #{exit_code}.\n\nError details:\n#{stderr_buffer}"
          Logger.error("Command error: #{error_message}")
          
          # Find linked processes and send error response
          if parent = Process.info(self(), :links) do
            Enum.each(elem(parent, 1), fn pid ->
              if is_pid(pid) and Process.alive?(pid) do
                # Format as a JSON-RPC error response
                error_response = %{
                  "jsonrpc" => "2.0",
                  "id" => 1,
                  "error" => %{
                    "code" => -32000,
                    "message" => error_message,
                    "data" => %{
                      "exit_code" => exit_code,
                      "stderr" => stderr_buffer
                    }
                  }
                }
                
                # Send the error response
                Logger.warning("Sending error response to client: #{inspect(pid)}")
                send(pid, {:transport_response, error_response})
              end
            end)
          end
          
          # Stop the process since we've handled the error
          {:stop, :normal, %{state | stderr_buffer: stderr_buffer}}
        else
          # No error marker, just update buffer
          {:noreply, %{state | stderr_buffer: stderr_buffer}}
        end
      
      String.starts_with?(data, "[STDOUT] ") ->
        # Handle stdout output - strip the prefix
        stdout_data = String.slice(data, 9, String.length(data))
        
        # For regular data processing, append to standard buffer
        new_buffer = state.buffer <> stdout_data
        
        # Process complete messages
        {messages, remaining_buffer} = extract_messages(new_buffer)
        
        # Send complete messages to the client
        Enum.each(messages, fn message ->
          # Log the message for debugging
          Logger.debug("Received message from process: #{inspect(message)}")
          
          # For each client listening to this process, forward the message
          # This is critical for stdio communication
          if parent = Process.info(self(), :links) do
            Enum.each(elem(parent, 1), fn pid ->
              if is_pid(pid) and Process.alive?(pid) do
                # Try to parse the message as JSON first, then forward
                case Jason.decode(message) do
                  {:ok, parsed} -> 
                    send(pid, {:transport_response, parsed})
                  _ -> 
                    # If not valid JSON, send the raw message
                    send(pid, {:transport_response, message})
                end
              end
            end)
          end
        end)
        
        {:noreply, %{state | buffer: remaining_buffer}}
      
      true ->
        # Fallback for untagged data (no wrapper or direct output)
        # Append new data to buffer
        new_buffer = state.buffer <> data
        
        # Process complete messages
        {messages, remaining_buffer} = extract_messages(new_buffer)
        
        # Send complete messages to the client
        Enum.each(messages, fn message ->
          # Log the message for debugging
          Logger.debug("Received untagged message from process: #{inspect(message)}")
          
          # For each client listening to this process, forward the message
          if parent = Process.info(self(), :links) do
            Enum.each(elem(parent, 1), fn pid ->
              if is_pid(pid) and Process.alive?(pid) do
                # Try to parse the message as JSON first, then forward
                case Jason.decode(message) do
                  {:ok, parsed} -> 
                    send(pid, {:transport_response, parsed})
                  _ -> 
                    # If not valid JSON, send the raw message
                    send(pid, {:transport_response, message})
                end
              end
            end)
          end
        end)
        
        {:noreply, %{state | buffer: remaining_buffer}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    # Enhanced logging for process termination
    Logger.warning(">>>>> Stdio transport process exited with status #{status} <<<<<")
    Logger.warning("Got exit_status message for port: #{inspect(port)}")
    Logger.warning("Our tracked port is: #{inspect(state.port)}")
    Logger.warning("Ports match: #{port == state.port}")
    
    # Try to get any buffered stderr content
    stderr_content = Map.get(state, :stderr_buffer, "")
    if stderr_content && stderr_content != "" do
      Logger.error("Stderr buffer at exit (status #{status}):\n#{stderr_content}")
    else
      Logger.warning("No stderr buffer available at process exit (status #{status})")
    end
    
    # For non-zero exit status, we need to notify any waiting clients
    # because otherwise they will time out waiting for initialize response
    if status != 0 do
      # Find all linked processes (clients) and send them an error
      if parent = Process.info(self(), :links) do
        error_message = if stderr_content && stderr_content != "" do
          "Command exited with status #{status}. Error: #{String.trim(stderr_content)}"
        else
          "Command exited with status #{status}"
        end
        
        # Send an error to each linked process
        Enum.each(elem(parent, 1), fn pid ->
          if is_pid(pid) and Process.alive?(pid) do
            # Format as a JSON-RPC error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => 1,
              "error" => %{
                "code" => -32000,
                "message" => error_message,
                "data" => %{
                  "exit_code" => status,
                  "stderr" => stderr_content
                }
              }
            }
            
            # Send as a transport response
            send(pid, {:transport_response, error_response})
          end
        end)
      end
    end
    
    # Return normal termination message, don't raise an exception
    # This is triggered normally when using the wrapper script
    if status == 0 do
      # Clean exit is normal when using wrapper script
      Logger.debug("Process terminated normally with status 0")
      {:stop, :normal, state}
    else
      # Non-zero status is an error, but we've already notified clients
      # so we can gracefully stop now
      Logger.error("Process terminated with error status #{status}")
      {:stop, {:exit, status}, state}
    end
  end
  
  @impl true
  def handle_info({port, :closed}, state) do
    Logger.warning("Port closed message received from #{inspect(port)}")
    
    # Check if this is our tracked port
    is_our_port = state.port == port
    Logger.debug("Is this our tracked port? #{is_our_port}")
    
    if is_our_port do
      # Check if we have any stderr buffer
      stderr_content = Map.get(state, :stderr_buffer, "")
      if stderr_content && stderr_content != "" do
        Logger.error("Stderr buffer at port closed:\n#{stderr_content}")
        
        # Find linked processes and send error
        if parent = Process.info(self(), :links) do
          error_message = "Command execution failed. Error output:\n#{stderr_content}"
          
          # Send an error to each linked process
          Enum.each(elem(parent, 1), fn pid ->
            if is_pid(pid) and Process.alive?(pid) do
              # Format as a JSON-RPC error response
              error_response = %{
                "jsonrpc" => "2.0",
                "id" => 1,
                "error" => %{
                  "code" => -32000,
                  "message" => error_message,
                  "data" => %{
                    "stderr" => stderr_content
                  }
                }
              }
              
              # Send as a transport response
              Logger.debug("Sending error response to client: #{inspect(pid)}")
              send(pid, {:transport_response, error_response})
            end
          end)
        end
      else
        Logger.warning("No stderr buffer available when port closed")
      end
      
      # Stop the process since the port is closed
      Logger.debug("Stopping process since port is closed")
      {:stop, :normal, state}
    else
      # Not our port, just continue
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in stdio transport: #{inspect(msg)}")
    Logger.debug("Our tracked port is: #{inspect(state.port)}")
    
    # Check if the port is still alive and get info
    if is_port(state.port) do
      port_info = Port.info(state.port)
      Logger.debug("Current port info: #{inspect(port_info)}")
    else
      Logger.debug("state.port is not a valid port: #{inspect(state.port)}")
    end
    
    # Handle different message types
    case msg do
      {port, _} when is_port(port) ->
        # This is a port-related message that we're not explicitly handling
        Logger.warning("Unhandled port message received: #{inspect(msg)}")
        port_info = Port.info(port)
        Logger.debug("Unhandled port info: #{inspect(port_info)}")
        
        # If this port matches our state's port, log that too
        if Map.get(state, :port) == port do
          Logger.warning("Message is from our tracked port")
        end
        
        {:noreply, state}
        
      {:DOWN, ref, :port, port, reason} ->
        # Port monitor message
        Logger.warning("Port monitor :DOWN message received: #{inspect(reason)}")
        # Check if this is our tracked port and our monitor ref
        # Note: state.port might be nil if the port was already closed or crashed
        our_port = Map.get(state, :port) == port
        our_ref = Map.get(state, :port_ref) == ref
        
        Logger.warning("DOWN message port matches our port: #{our_port}")
        Logger.warning("DOWN message ref matches our ref: #{our_ref}")
        Logger.warning("Our current port is: #{inspect(Map.get(state, :port))}")
        
        # If our current port is nil but the ref matches, this is still our port
        # This can happen if the port died unexpectedly
        if our_port || our_ref || (Map.get(state, :port) == nil && Map.get(state, :port_ref) == ref) do
          # This is for our tracked port, handle as a port exit
          Logger.warning("DOWN message is for our tracked port, handling as port exit")
          
          # Try to get any buffered stderr content
          stderr_content = Map.get(state, :stderr_buffer, "")
          if stderr_content && stderr_content != "" do
            Logger.error("Stderr buffer at port down:\n#{stderr_content}")
            
            # Find linked processes and send error
            if parent = Process.info(self(), :links) do
              error_message = "Command failed. Error output:\n#{stderr_content}"
              
              # Send an error to each linked process
              Enum.each(elem(parent, 1), fn pid ->
                if is_pid(pid) and Process.alive?(pid) do
                  # Format as a JSON-RPC error response
                  error_response = %{
                    "jsonrpc" => "2.0",
                    "id" => 1,
                    "error" => %{
                      "code" => -32000,
                      "message" => error_message,
                      "data" => %{
                        "stderr" => stderr_content
                      }
                    }
                  }
                  
                  # Send as a transport response
                  Logger.debug("Sending error response to client: #{inspect(pid)}")
                  send(pid, {:transport_response, error_response})
                end
              end)
            end
          end
          
          # Stop the GenServer with the reason from the DOWN message
          {:stop, {:port_down, reason}, state}
        else
          # Not our port or ref, just continue
          {:noreply, state}
        end
        
      _ ->
        # Some other message type
        {:noreply, state}
    end
  end

  # Private helpers

  # Extract complete JSON-RPC messages from the buffer
  defp extract_messages(buffer) do
    extract_messages(buffer, [])
  end

  defp extract_messages(buffer, acc) do
    case find_message_boundary(buffer) do
      {message, rest} ->
        extract_messages(rest, [message | acc])
      :incomplete ->
        {Enum.reverse(acc), buffer}
    end
  end
  
  # Find a complete message in the buffer
  # This implementation assumes that each message is terminated by a newline
  defp find_message_boundary(buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [message, rest] ->
        trimmed = String.trim(message)
        if trimmed != "" do
          {trimmed, rest}
        else
          # Skip empty lines and continue parsing
          find_message_boundary(rest)
        end
      [_incomplete] ->
        :incomplete
    end
  end
end