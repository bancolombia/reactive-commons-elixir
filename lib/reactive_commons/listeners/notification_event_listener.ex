defmodule NotificationEventListener do
  use GenericListener, handlers_table: :notification_event_handlers, executor: NotificationEventExecutor

  @impl true
  def should_listen(), do: ListenersValidator.has_handlers(get_handlers())

  def get_handlers(), do: MessageContext.handlers().notification_event_listeners

  @impl true
  def initial_state() do
    %{prefetch_count: MessageContext.prefetch_count()}
  end

  @impl true
  def create_topology(chan, state) do
    #Topology
    stop_and_delete(state)

    queue_name = MessageContext.gen_notification_event_queue_name()
    events_exchange_name = MessageContext.events_exchange_name()
    #Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    #Queue
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    # Bindings
    for {event_name, _handler} <- :ets.tab2list(@handlers_table) do
      :ok = AMQP.Queue.bind(chan, queue_name, events_exchange_name, routing_key: event_name)
    end
    {:ok, %{state | queue_name: queue_name}}
  end

end
