defmodule MCPEx.Transport.Stdio do
  @moduledoc """
  Implementation of the MCP transport over standard I/O.

  This transport spawns an external process and communicates with it over
  standard input/output pipes. It handles encoding/decoding of messages
  and manages the lifecycle of the external process.
  """

  use GenServer
  require Logger

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

    try do
      # Check if we should use CommandUtils for enhanced shell environment
      if use_shell_env && Code.ensure_loaded?(MCPEx.Utils.CommandUtils) do
        Logger.debug("Using direct Port.open approach for shell-wrapped command")
        
        # For shell-wrapped commands, we don't need to add an additional shell layer
        # Instead, open the port directly with the given command and args
        port = Port.open(
          {:spawn_executable, String.to_charlist(command)},
          port_options ++ [{:args, Enum.map(args, &String.to_charlist/1)}]
        )
        
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
        result = {:ok, port, os_pid}
        
        case result do
          {:ok, port, os_pid} ->
            Logger.debug("Started command through shell with PID: #{os_pid}")
            {:ok, %{port: port, buffer: ""}}
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
            {exec_path, exec_args} = if use_wrapper do
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
            {:ok, %{port: port, buffer: ""}}
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
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Append new data to buffer
    new_buffer = state.buffer <> data
    
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
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Stdio transport process exited with status #{status}")
    
    # Return normal termination message, don't raise an exception
    # This is triggered normally when using the wrapper script
    if status == 0 do
      # Clean exit is normal when using wrapper script
      {:stop, :normal, state}
    else
      # Non-zero status is an error
      {:stop, {:exit, status}, state}
    end
  end
  
  @impl true
  def handle_info({port, :closed}, %{port: port} = state) do
    Logger.warning("Port closed message received")
    # Just note it and continue
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in stdio transport: #{inspect(msg)}")
    {:noreply, state}
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