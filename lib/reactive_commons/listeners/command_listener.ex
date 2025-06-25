defmodule CommandListener do
  @moduledoc false
  use GenericListener, executor: CommandExecutor

  alias MessageContext

  @impl true
  def should_listen(broker) do
    ListenersValidator.has_handlers(get_handlers(broker))
  end

  def get_handlers(broker) do
    MessageContext.handlers(broker).command_listeners
  end

  @impl true
  def initial_state(broker) do
    queue_name = MessageContext.command_queue_name(broker)
    prefetch_count = MessageContext.prefetch_count(broker)
    %{prefetch_count: prefetch_count, queue_name: queue_name, broker: broker}
  end

  @impl true
  def create_topology(chan, state) do
    # Topology
    broker = state.broker
    direct_exchange_name = MessageContext.direct_exchange_name(broker)
    command_queue_name = MessageContext.command_queue_name(broker)
    # Exchange
    :ok = AMQP.Exchange.declare(chan, direct_exchange_name, :direct, durable: true)
    # Queue
    if MessageContext.with_dlq_retry(broker) do
      :ok = AMQP.Exchange.declare(chan, direct_exchange_name <> ".DLQ", :direct, durable: true)

      {:ok, _} =
        AMQP.Queue.declare(
          chan,
          command_queue_name,
          durable: true,
          arguments: [{"x-dead-letter-exchange", :longstr, direct_exchange_name <> ".DLQ"}]
        )

      {:ok, _} =
        declare_dlq(chan, command_queue_name, direct_exchange_name, MessageContext.retry_delay(broker))

      :ok =
        AMQP.Queue.bind(
          chan,
          command_queue_name <> ".DLQ",
          direct_exchange_name <> ".DLQ",
          routing_key: command_queue_name
        )
    else
      {:ok, _} = AMQP.Queue.declare(chan, command_queue_name, durable: true)
    end

    :ok =
      AMQP.Queue.bind(
        chan,
        command_queue_name,
        direct_exchange_name,
        routing_key: command_queue_name
      )

    {:ok, state}
  end
end