defmodule ReplyListener do
  @moduledoc false
  use GenericListener
  require Logger

  @impl true
  def should_listen(broker),
    do: ListenersValidator.should_listen_replies(MessageContext.config(broker))

  @impl true
  def initial_state(broker) do
    %{prefetch_count: MessageContext.prefetch_count(broker), broker: broker}
  end

  @impl true
  def create_topology(chan, state) do
    # Topology
    broker = state.broker
    stop_and_delete(state)
    queue_name = MessageContext.gen_reply_queue_name(broker)
    exchange_name = MessageContext.reply_exchange_name(broker)
    routing_key = MessageContext.reply_routing_key(broker)

    # Exchange
    :ok = AMQP.Exchange.declare(chan, exchange_name, :topic, durable: true)
    # Queue
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    # Bindings
    :ok = AMQP.Queue.bind(chan, queue_name, exchange_name, routing_key: routing_key)
    {:ok, %{state | queue_name: queue_name}}
  end

  def consume(props, payload, %{chan: chan, broker: broker}) do
    correlation_id = get_correlation_id(props)
    :ok = AMQP.Basic.ack(chan, props.delivery_tag)
    result = ReplyRouter.route_reply(broker, correlation_id, payload)
    :telemetry.execute([:async, :message, :replied], %{}, %{meta: props, result: result})
    result
  end
end
