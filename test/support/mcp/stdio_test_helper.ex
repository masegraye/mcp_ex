defmodule MCPEx.Test.StdioTestHelper do
  @moduledoc """
  Helper functions for testing the MCPEx client with stdio-based MCP servers.
  
  This module provides functions to:
  1. Set up a temporary directory with test files
  2. Start a filesystem MCP server (using npx) with access to this directory
  3. Connect an MCPEx client to this server via stdio transport
  4. Clean up resources when tests complete
  """

  alias MCPEx.Client
  
  @doc """
  Creates a temporary directory with test files and starts a filesystem MCP server.
  
  Returns:
  * `{:ok, %{temp_dir: path, client: client}}` - The setup was successful
  * `{:error, reason}` - The setup failed
  
  ## Examples
  
      iex> {:ok, %{temp_dir: temp_dir, client: client}} = MCPEx.Test.StdioTestHelper.setup_stdio_test()
      iex> # Use client for operations
      iex> MCPEx.Test.StdioTestHelper.teardown_stdio_test(temp_dir, client)
  """
  @spec setup_stdio_test() :: {:ok, %{temp_dir: String.t(), client: Client.t()}} | {:error, term()}
  def setup_stdio_test do
    # Create temporary directory inside the project's build directory for better access
    build_dir = Path.join([File.cwd!(), "_build", "test"])
    File.mkdir_p!(build_dir)
    
    # Create test directory with timestamp
    temp_dir = Path.join(build_dir, "mcp_ex_test_#{:os.system_time(:millisecond)}")
    File.mkdir_p!(temp_dir)
    
    # We'll keep this log for test debugging purposes
    if Mix.env() == :test, do: IO.puts("Created test directory at: #{temp_dir}")
    
    # Create some test files
    test_file_path = Path.join(temp_dir, "test_file.txt")
    File.write!(test_file_path, "This is a test file content.\nLine 2\nLine 3")
    
    # Create a test directory with a nested file
    test_dir = Path.join(temp_dir, "test_dir")
    File.mkdir_p!(test_dir)
    File.write!(Path.join(test_dir, "nested_file.txt"), "This is a nested file.")
    
    # Start the filesystem MCP server with access to the temp directory
    # Check if npx is available in PATH - output warning if not
    case System.find_executable("npx") do
      nil -> IO.puts("Warning: npx not found in PATH, test will likely fail")
      _npx_path -> :ok
    end
    
    # Create a timestamp for this test run to uniquely identify files
    timestamp = :os.system_time(:millisecond)
    
    # Create a temporary script to make sure we execute npx correctly
    script_path = Path.join(temp_dir, "mcp_npx_wrapper_#{timestamp}.sh")
    script_content = """
    #!/bin/sh
    # Wrapper script to ensure consistent NPX execution
    
    # Debug output to stderr
    echo "Starting NPX wrapper with path $PATH" >&2
    echo "Executing npx command to access directory: #{temp_dir}" >&2
    
    # Ensure directory has correct permissions
    chmod -R 755 #{temp_dir}
    
    # Execute the npx command directly - errors go to stderr only 
    npx -y @modelcontextprotocol/server-filesystem #{temp_dir}
    """
    
    # Write script path to a file so we can clean it up later
    marker_path = System.tmp_dir!() |> Path.join("mcp_test_marker_#{timestamp}.txt")
    File.write!(marker_path, script_path)
    
    File.write!(script_path, script_content)
    File.chmod!(script_path, 0o755)
    
    # Start the MCPEx client with stdio transport using the wrapper script
    client_result = Client.start_link(
      transport: :stdio,
      command: script_path,
      capabilities: [:resources, :tools]
    )
    
    case client_result do
      {:ok, client} -> 
        {:ok, %{temp_dir: temp_dir, client: client}}
      error -> 
        # Clean up temp directory if client fails to start
        File.rm_rf!(temp_dir)
        error
    end
  end
  
  @doc """
  Cleans up resources used by the stdio test.
  
  ## Parameters
  
  * `temp_dir` - The temporary directory to remove
  * `client` - The MCPEx client to stop
  """
  @spec teardown_stdio_test(String.t(), Client.t()) :: :ok
  def teardown_stdio_test(temp_dir, client) do
    # Stop the client
    Client.stop(client)
    
    # Remove the temporary directory
    File.rm_rf!(temp_dir)
    
    # Clean up marker files - these are used to track script files
    marker_paths = Path.wildcard(Path.join(System.tmp_dir!(), "mcp_test_marker_*.txt"))
    
    # No need to clean up script files separately - they're in the temp_dir which we're removing
    Enum.each(marker_paths, fn marker_path ->
      File.rm!(marker_path)
    end)
    
    # Cleanup log for test debugging
    if Mix.env() == :test, do: IO.puts("Cleaned up test directory: #{temp_dir}")
    
    :ok
  end
end