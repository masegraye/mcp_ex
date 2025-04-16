defmodule MCPEx.Sampling.Handler do
  @moduledoc """
  Behaviour for implementing MCP sampling request handlers.
  
  This behaviour defines the contract for processing sampling requests from MCP servers.
  Implementations are responsible for model selection, user approval, and LLM interaction.
  
  ## Usage
  
  Handler implementations should implement the `process_sampling_request/5` callback.
  Handlers can be registered with an MCPEx.Client when starting it:
  
  ```elixir
  # Register a handler with configuration
  {:ok, client} = MCPEx.Client.start_link(
    transport: :stdio,
    sampling_handler: {MyApp.SamplingHandler, [api_key: "sk_123", user_id: "user_1"]}
  )
  ```
  
  The handler_config (second element of the tuple) can be any term and will be passed
  to the handler's callbacks. This allows for stateful operation by passing PIDs or
  other references that the handler can use to access state.
  """
  
  @doc """
  Processes a sampling request from an MCP server.
  
  ## Parameters
  
  * `request_id` - The ID of the request for correlation
  * `messages` - The conversation history to send to the LLM
  * `model_preferences` - Preferences for model selection
  * `request_options` - Options specific to this request (system_prompt, max_tokens, etc.)
  * `handler_config` - Configuration provided when the handler was registered
  
  ## Returns
  
  * `{:ok, response}` - The LLM response
  * `{:error, reason}` - The request failed or was rejected
  """
  @callback process_sampling_request(
    request_id :: String.t(),
    messages :: list(map()),
    model_preferences :: map(),
    request_options :: map(),
    handler_config :: term()
  ) :: {:ok, map()} | {:error, term()}
end