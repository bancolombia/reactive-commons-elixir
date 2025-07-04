defmodule NotificationEventListener do
  @moduledoc false
  use GenericListener,
    handlers_table: :notification_event_handlers,
    executor: NotificationEventExecutor

  @impl true
  def should_listen(broker), do: ListenersValidator.has_handlers(get_handlers(broker))

  def get_handlers(broker), do: MessageContext.handlers(broker).notification_event_listeners

  @impl true
  def initial_state(broker, table) do
    %{prefetch_count: MessageContext.prefetch_count(broker), broker: broker, table: table}
  end

  @impl true
  def create_topology(chan, state = %{broker: broker, table: table}) do
    # Topology
    stop_and_delete(state)
    queue_name = MessageContext.gen_notification_event_queue_name(broker)
    events_exchange_name = MessageContext.events_exchange_name(broker)
    # Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    # Queue
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    # Bindings
    for {_namespace, handlers} <- :ets.tab2list(table),
        {event_name, _handler} <- handlers do
      :ok = AMQP.Queue.bind(chan, queue_name, events_exchange_name, routing_key: event_name)
    end

    {:ok, %{state | queue_name: queue_name}}
  end
end
