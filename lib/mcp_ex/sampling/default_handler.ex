defmodule MCPEx.Sampling.DefaultHandler do
  @moduledoc """
  A default implementation of the sampling handler.
  
  This handler provides a basic implementation that simply returns an error indicating
  that no actual LLM integration is configured. It's useful as a reference implementation
  and for testing.
  
  Applications should implement their own handlers that integrate with actual LLM providers.
  """
  
  @behaviour MCPEx.Sampling.Handler
  
  @impl true
  def process_sampling_request(request_id, messages, model_preferences, request_options, handler_config) do
    # Log the request for debugging
    IO.puts("Received sampling request #{request_id}")
    IO.puts("Messages: #{inspect(messages)}")
    IO.puts("Model preferences: #{inspect(model_preferences)}")
    IO.puts("Request options: #{inspect(request_options)}")
    IO.puts("Handler config: #{inspect(handler_config)}")
    
    # Return a default error response
    model_name = get_model_hint(model_preferences)
    
    if handler_config[:simulator_mode] do
      # In simulator mode, return a mock response
      {:ok, %{
        role: "assistant",
        content: %{
          type: "text",
          text: "This is a simulated response from the DefaultHandler. To get actual LLM responses, " <>
                "please implement a custom sampling handler with a real LLM provider integration."
        },
        model: model_name || "simulated-model",
        stop_reason: "endTurn"
      }}
    else
      # In normal mode, return an error
      {:error, %{
        code: -32603, # Internal error code
        message: "No LLM integration configured. Please implement a custom MCPEx.Sampling.Handler."
      }}
    end
  end
  
  # Helper to extract a model hint for display purposes
  defp get_model_hint(model_preferences) do
    case get_in(model_preferences, ["hints"]) || get_in(model_preferences, [:hints]) do
      nil -> nil
      [] -> nil
      hints ->
        # Find the first hint with a name
        hint = Enum.find(hints, &(Map.has_key?(&1, "name") || Map.has_key?(&1, :name)))
        case hint do
          nil -> nil
          %{"name" => name} -> name
          %{name: name} -> name
          _ -> nil
        end
    end
  end
end