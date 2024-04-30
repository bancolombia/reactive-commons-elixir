defmodule ReplyListener do
  @moduledoc false
  use GenericListener

  @impl true
  def should_listen, do: ListenersValidator.should_listen_replies(MessageContext.config())

  @impl true
  def initial_state do
    %{prefetch_count: MessageContext.prefetch_count()}
  end

  @impl true
  def create_topology(chan, state) do
    # Topology
    stop_and_delete(state)

    queue_name = MessageContext.gen_reply_queue_name()
    exchange_name = MessageContext.reply_exchange_name()
    routing_key = MessageContext.reply_routing_key()
    # Exchange
    :ok = AMQP.Exchange.declare(chan, exchange_name, :topic, durable: true)
    # Queue
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    # Bindings
    :ok = AMQP.Queue.bind(chan, queue_name, exchange_name, routing_key: routing_key)
    {:ok, %{state | queue_name: queue_name}}
  end

  def consume(props, payload, %{chan: chan}) do
    correlation_id = get_correlation_id(props)
    :ok = AMQP.Basic.ack(chan, props.delivery_tag)
    ReplyRouter.route_reply(correlation_id, payload)
  end
end
