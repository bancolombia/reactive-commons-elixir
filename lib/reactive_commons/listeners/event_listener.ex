defmodule EventListener do
  @moduledoc false
  use GenericListener, executor: EventExecutor

  @impl true
  def should_listen(broker), do: ListenersValidator.has_handlers(get_handlers(broker))

  def get_handlers(broker), do: MessageContext.handlers(broker).event_listeners

  @impl true
  def initial_state(broker, table) do
    queue_name = MessageContext.event_queue_name(broker)
    prefetch_count = MessageContext.prefetch_count(broker)
    %{prefetch_count: prefetch_count, queue_name: queue_name, broker: broker, table: table}
  end

  @impl true
  def create_topology(chan, state = %{broker: broker, table: table}) do
    # Topology
    event_queue_name = MessageContext.event_queue_name(broker)
    events_exchange_name = MessageContext.events_exchange_name(broker)
    app_name = MessageContext.application_name(broker)
    retry_delay = MessageContext.retry_delay(broker)
    # Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    # Queue
    if MessageContext.with_dlq_retry(broker) do
      retry_exchange_name = "#{app_name}.#{events_exchange_name}"
      events_dlq_exchange_name = "#{retry_exchange_name}.DLQ"
      :ok = AMQP.Exchange.declare(chan, retry_exchange_name, :topic, durable: true)
      :ok = AMQP.Exchange.declare(chan, events_dlq_exchange_name, :topic, durable: true)
      declare_dlq(chan, event_queue_name, retry_exchange_name, retry_delay)

      {:ok, _} =
        AMQP.Queue.declare(
          chan,
          event_queue_name,
          durable: true,
          arguments: [{"x-dead-letter-exchange", :longstr, events_dlq_exchange_name}]
        )

      :ok =
        AMQP.Queue.bind(chan, event_queue_name <> ".DLQ", events_dlq_exchange_name,
          routing_key: "#"
        )

      :ok = AMQP.Queue.bind(chan, event_queue_name, retry_exchange_name, routing_key: "#")
    else
      {:ok, _} = AMQP.Queue.declare(chan, event_queue_name, durable: true)
    end

    # Bindings
    for {_namespace, handlers} <- :ets.tab2list(table),
        {event_name, _handler} <- handlers do
      :ok = AMQP.Queue.bind(chan, event_queue_name, events_exchange_name, routing_key: event_name)
    end

    {:ok, state}
  end

end
