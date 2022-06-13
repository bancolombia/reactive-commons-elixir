defmodule EventListener do
  use GenericListener, handlers_table: :event_handlers, executor: EventExecutor

  @impl true
  def should_listen(), do: ListenersValidator.has_handlers(get_handlers())

  def get_handlers(), do: MessageContext.handlers().event_listeners

  @impl true
  def initial_state() do
    queue_name = MessageContext.event_queue_name()
    prefetch_count = MessageContext.prefetch_count()
    %{prefetch_count: prefetch_count, queue_name: queue_name}
  end

  @impl true
  def create_topology(chan) do
    #Topology
    event_queue_name = MessageContext.event_queue_name()
    events_exchange_name = MessageContext.events_exchange_name()
    app_name = MessageContext.application_name()
    retry_delay = MessageContext.retry_delay()
    #Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    #Queue
    if MessageContext.with_dlq_retry() do
      retry_exchange_name = "#{app_name}.#{events_exchange_name}"
      events_dlq_exchange_name = "#{retry_exchange_name}.DLQ"
      :ok = AMQP.Exchange.declare(chan, retry_exchange_name, :topic, durable: true)
      :ok = AMQP.Exchange.declare(chan, events_dlq_exchange_name, :topic, durable: true)
      declare_dlq(chan, event_queue_name, retry_exchange_name, retry_delay)
      {:ok, _} = AMQP.Queue.declare(
        chan,
        event_queue_name,
        durable: true,
        arguments: [{"x-dead-letter-exchange", :longstr, events_dlq_exchange_name}]
      )
      :ok = AMQP.Queue.bind(chan, event_queue_name <> ".DLQ", events_dlq_exchange_name, routing_key: "#")
      :ok = AMQP.Queue.bind(chan, event_queue_name, retry_exchange_name, routing_key: "#")
    else
      {:ok, _} = AMQP.Queue.declare(chan, event_queue_name, durable: true)
    end
    # Bindings
    for {event_name, _handler} <- :ets.tab2list(@handlers_table) do
      :ok = AMQP.Queue.bind(chan, event_queue_name, events_exchange_name, routing_key: event_name)
    end
    # Remove bindings for explicit discarded events
    for event_name <- Map.keys(MessageContext.handlers().discarded_events) do
      :ok = AMQP.Queue.unbind(chan, event_queue_name, events_exchange_name, routing_key: event_name)
    end
    :ok
  end

  def drop_topology(conn), do: delete_queue(conn, MessageContext.event_queue_name())

end
