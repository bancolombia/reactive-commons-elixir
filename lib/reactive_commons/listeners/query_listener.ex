defmodule QueryListener do
  @moduledoc false
  use GenericListener, executor: QueryExecutor

  @impl true
  def should_listen(broker), do: ListenersValidator.has_handlers(get_handlers(broker))

  def get_handlers(broker), do: MessageContext.handlers(broker).query_listeners

  @impl true
  def initial_state(broker) do
    queue_name = MessageContext.query_queue_name(broker)
    prefetch_count = MessageContext.prefetch_count(broker)
    %{prefetch_count: prefetch_count, queue_name: queue_name, broker: broker}
  end

  @impl true
  def create_topology(chan, state) do
    # Topology
    broker = state.broker
    direct_exchange_name = MessageContext.direct_exchange_name(broker)
    query_queue_name = MessageContext.query_queue_name(broker)

    # Exchange
    :ok = AMQP.Exchange.declare(chan, direct_exchange_name, :direct, durable: true)
    # Queue
    if MessageContext.with_dlq_retry(broker) do
      :ok = AMQP.Exchange.declare(chan, direct_exchange_name <> ".DLQ", :direct, durable: true)

      {:ok, _} =
        AMQP.Queue.declare(
          chan,
          query_queue_name,
          durable: true,
          arguments: [{"x-dead-letter-exchange", :longstr, direct_exchange_name <> ".DLQ"}]
        )

      {:ok, _} =
        declare_dlq(chan, query_queue_name, direct_exchange_name, MessageContext.retry_delay(broker))

      :ok =
        AMQP.Queue.bind(
          chan,
          query_queue_name <> ".DLQ",
          direct_exchange_name <> ".DLQ",
          routing_key: query_queue_name
        )
    else
      {:ok, _} = AMQP.Queue.declare(chan, query_queue_name, durable: true)
    end

    # Bindings
    :ok =
      AMQP.Queue.bind(chan, query_queue_name, direct_exchange_name, routing_key: query_queue_name)

    {:ok, state}
  end
end
