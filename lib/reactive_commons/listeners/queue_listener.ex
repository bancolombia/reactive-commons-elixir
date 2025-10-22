defmodule QueueListener do
  @moduledoc false
  require Logger
  use GenericListener, executor: QueueExecutor

  @impl true
  def should_listen(broker), do: broker != nil

  def get_handlers(%{broker: broker, queue_name: queue_name}) do
    queue_handlers = Map.get(MessageContext.handlers(broker).queue_listeners, broker, %{})

    default_handler = fn msg ->
      Logger.warning(
        "No handler found for queue listener #{queue_name} in broker #{broker} for message #{inspect(msg)}"
      )
    end

    handler = Map.get(queue_handlers, queue_name, default_handler)

    Map.put(%{}, broker, %{
      "default" => handler
    })
  end

  @impl true
  def initial_state(%{broker: broker, queue_name: queue_name}, table) do
    prefetch_count = MessageContext.prefetch_count(broker)
    %{prefetch_count: prefetch_count, queue_name: queue_name, broker: broker, table: table}
  end

  @impl true
  def create_topology(_chan, state) do
    {:ok, state}
  end

  def get_childrens(broker) do
    Map.get(MessageContext.handlers(broker).queue_listeners, broker, %{})
    |> Enum.map(fn {queue, _handler} ->
      {QueueListener, %{broker: broker, queue_name: queue}}
    end)
  rescue
    error ->
      Logger.warning("Error getting queue handlers #{inspect(error)}")
      []
  end
end
