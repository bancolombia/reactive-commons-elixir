defmodule NotificationEventListener do
  @moduledoc false
  use GenericListener,
    handlers_table: :notification_event_handlers,
    executor: NotificationEventExecutor

  @impl true
  def should_listen(broker), do: ListenersValidator.has_handlers(get_handlers(broker))

  def get_handlers(broker), do: MessageContext.handlers(broker).notification_event_listeners

  @impl true
  def initial_state(broker) do
    %{prefetch_count: MessageContext.prefetch_count(broker), broker: broker}
  end

  @impl true
  def create_topology(chan, state) do
    # Topology
    broker = state.broker
    stop_and_delete(state)
    queue_name = MessageContext.gen_notification_event_queue_name(broker)
    events_exchange_name = MessageContext.events_exchange_name(broker)
    # Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    # Queue
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    # Bindings
    for {_namespace, handlers} <- :ets.tab2list(table_name(broker)),
        {event_name, _handler} <- handlers do
      :ok = AMQP.Queue.bind(chan, queue_name, events_exchange_name, routing_key: event_name)
    end

    {:ok, %{state | queue_name: queue_name}}
  end

  defp table_name(broker), do: :"handler_table_#{build_name(__MODULE__, broker)}"

  defp build_name(module, broker) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("_" <> to_string(broker))
    |> String.to_atom()
  end
end
