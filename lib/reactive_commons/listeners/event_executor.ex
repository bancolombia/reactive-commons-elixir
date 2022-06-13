defmodule EventExecutor do
  use GenericExecutor, type: :event
  require Logger

  def get_handler_path(%{meta: %{routing_key: routing_key}}, _), do: routing_key

  def when_no_handler(event_name) do
    if Map.has_key?(MessageContext.handlers().discarded_events, event_name) do
      {:ok, fn message -> Logger.info("Discarding event #{inspect(message)}") end}
    else
      {:error, :no_handler_for,  @message_type, event_name}
    end
  end

end

