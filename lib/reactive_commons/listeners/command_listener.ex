defmodule CommandListener do
  use GenericListener, handlers_table: :command_handlers, executor: CommandExecutor

  @impl true
  def should_listen(), do: ListenersValidator.has_handlers(get_handlers())

  def get_handlers(), do: MessageContext.handlers().command_listeners

  @impl true
  def initial_state() do
    queue_name = MessageContext.command_queue_name()
    prefetch_count = MessageContext.prefetch_count()
    %{prefetch_count: prefetch_count, queue_name: queue_name}
  end

  @impl true
  def create_topology(chan) do
    #Topology
    direct_exchange_name = MessageContext.direct_exchange_name()
    command_queue_name = MessageContext.command_queue_name()
    #Exchange
    :ok = AMQP.Exchange.declare(chan, direct_exchange_name, :direct, durable: true)
    #Queue
    if MessageContext.with_dlq_retry() do
      :ok = AMQP.Exchange.declare(chan, direct_exchange_name <> ".DLQ", :direct, durable: true)
      {:ok, _} = AMQP.Queue.declare(
        chan,
        command_queue_name,
        durable: true,
        arguments: [{"x-dead-letter-exchange", :longstr, direct_exchange_name <> ".DLQ"}]
      )
      {:ok, _} = declare_dlq(chan, command_queue_name, direct_exchange_name, MessageContext.retry_delay())
      :ok = AMQP.Queue.bind(
        chan,
        command_queue_name <> ".DLQ",
        direct_exchange_name <> ".DLQ",
        routing_key: command_queue_name
      )
    else
      {:ok, _} = AMQP.Queue.declare(chan, command_queue_name, durable: true)
    end
    #Bindings
    :ok = AMQP.Queue.bind(chan, command_queue_name, direct_exchange_name, routing_key: command_queue_name)
  end

end
