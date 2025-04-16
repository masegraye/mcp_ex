defmodule MCPEx.Utils.CommandUtils do
  @moduledoc """
  Utility functions for finding executables and executing commands through the shell.
  Used by various parts of the library that need to interact with the system shell.
  """

  require Logger

  @doc """
  Gets the user's shell executable path and name.
  Returns a tuple of {shell_path, shell_name} where shell_path is the full path
  to the shell executable and shell_name is the base name (zsh, bash, etc).
  Falls back to /bin/bash if SHELL is not set.
  """
  def get_user_shell do
    # Get the current shell from environment or default to /bin/bash
    shell_path = System.get_env("SHELL") || "/bin/bash"
    shell_name = Path.basename(shell_path)

    {shell_path, shell_name}
  end

  @doc """
  Executes a command through the user's shell to ensure
  it has access to the full shell environment, including PATH from
  startup files (.zshrc, .bashrc, etc).

  Returns {output, exit_code}
  """
  def execute_through_shell(command) do
    {shell_path, shell_name} = get_user_shell()
    mix_env = System.get_env("MIX_ENV") || "dev"
    Logger.debug("Executing shell command in #{mix_env} environment using #{shell_name}")

    # In production, we may not be able to use interactive shell
    # Try multiple approaches in order of preference
    shell_approaches = if mix_env == "prod" do
      [
        # In dev, try interactive shell first (most complete environment)
        {shell_path, ["-i", "-c", command]},

        # Then try login shell
        {shell_path, ["-l", "-c", command]},

        # Then plain command
        {shell_path, ["-c", command]},

        # Fallback to /bin/sh as a last resort
        {"/bin/sh", ["-c", command]}
      ]
    else
      [
        # In dev, try interactive shell first (most complete environment)
        {shell_path, ["-i", "-c", command]},
        # Then try login shell
        {shell_path, ["-l", "-c", command]},
        # Then plain command
        {shell_path, ["-c", command]}
      ]
    end

    # Try each approach in sequence until one succeeds
    Enum.reduce_while(shell_approaches, {"", 1}, fn {cmd, args}, _acc ->
      try do
        Logger.debug("Attempting to execute '#{command}' with: #{cmd} #{Enum.join(args, " ")}")
        result = System.cmd(cmd, args, stderr_to_stdout: false)
        {:halt, result}  # Success! Return the result
      rescue
        e ->
          Logger.warning("Approach failed - #{cmd} #{hd(args)}: #{inspect(e)}")
          {:cont, {"", 1}}  # Try the next approach
      end
    end)
  end

  @doc """
  Find an executable in the PATH using the user's shell environment.
  Returns the full path to the executable or nil if not found.
  Falls back to system PATH search if shell environment fails.
  """
  def find_executable(command) do
    # First try using the enhanced shell environment
    {output, exit_code} = execute_through_shell("which #{command}")

    if exit_code == 0 && String.trim(output) != "" do
      executable_path = String.trim(output)
      if File.exists?(executable_path) do
        Logger.debug("Found executable '#{command}' at path: #{executable_path} using shell")
        executable_path
      else
        Logger.warning("Path returned by shell doesn't exist: #{executable_path}")
        try_fallback_search(command)
      end
    else
      Logger.warning("Shell which command failed, trying fallback search")
      try_fallback_search(command)
    end
  end

  # Fallback methods for finding executables when shell integration fails
  defp try_fallback_search(command) do
    import Bitwise, only: [&&&: 2]
    # Try common paths where executables might be found
    potential_paths = [
      # System paths
      "/usr/bin/#{command}",
      "/usr/local/bin/#{command}",
      "/bin/#{command}",
      "/opt/homebrew/bin/#{command}",
      # Docker is often in these locations
      "/usr/local/bin/docker",
      "/opt/homebrew/bin/docker",
      # Path for standard shells
      "/bin/sh",
      "/bin/bash",
      "/bin/zsh"
    ]

    # Only check paths relevant to the command we're looking for
    paths_to_check = if command in ["sh", "bash", "zsh"] do
      # Look in standard shell locations
      Enum.filter(potential_paths, fn path ->
        String.ends_with?(path, command) && String.starts_with?(path, "/bin/")
      end)
    else
      # For other commands, check standard locations
      Enum.filter(potential_paths, fn path -> String.ends_with?(path, command) end)
    end

    # Check if any of these paths exist and are executable
    found_path = Enum.find(paths_to_check, fn path ->
      File.exists?(path) && File.regular?(path) && File.stat!(path).mode &&& 0o111 != 0
    end)

    # If a path was found, use it
    if found_path do
      Logger.info("Found executable '#{command}' at fallback path: #{found_path}")
      found_path
    else
      # Last resort - try OS's find_executable (uses PATH from system env)
      case :os.find_executable(String.to_charlist(command)) do
        false ->
          Logger.warning("Could not find executable '#{command}' in system PATH")
          nil
        path_charlist ->
          path = List.to_string(path_charlist)
          Logger.info("Found executable '#{command}' with system search: #{path}")
          path
      end
    end
  end

  @doc """
  Convert string to charlist for Port.open, returns nil if input is nil
  """
  def to_charlist_if_found(nil), do: nil
  def to_charlist_if_found(path), do: String.to_charlist(path)
end