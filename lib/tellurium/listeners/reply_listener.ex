defmodule ReplyListener do
  use GenServer
  require Logger

  defstruct [:chan, :conn, :consumer_tag, :conn_pid]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    IO.puts("###########INITIALIZING#############")
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, %__MODULE__{}}
  end

  def handle_info({:connected, conn}, state = %{conn_pid: conn_pid}) do
    IO.puts("###########REPLY_LISTENER#############")
    IO.puts("Started!")
    {:ok, chan} = AMQP.Channel.open(conn)
    {:ok, consumer_tag} = init_bindings(chan)
    {:noreply, %{state | chan: chan, conn: conn, consumer_tag: consumer_tag}}
  end

  defp init_bindings(chan) do
    queue_name = MessageContext.reply_queue_name()
    exchange_name = MessageContext.reply_exchange_name()
    routing_key = MessageContext.reply_routing_key()
    {:ok, _} = AMQP.Queue.declare(chan, queue_name, auto_delete: true, exclusive: true)
    :ok = AMQP.Exchange.declare(chan, exchange_name, :topic, durable: true)
    :ok = AMQP.Queue.bind(chan, queue_name, exchange_name, routing_key: routing_key)
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue_name)
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Reply consumer registered: #{inspect(consumer_tag)}")
    {:noreply, %{state | consumer_tag: consumer_tag}}
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.error("Reply listener consumer stoped by the broker")
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("Reply listener consumer cancelled!")
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, props = %{delivery_tag: tag, redelivered: redelivered}}, state = %{chan: chan}) do
    consume(props, payload, chan)
    {:noreply, state}
  end

  defp consume(props, payload, chan) do
    correlation_id = get_correlation_id(props)
    :ok = AMQP.Basic.ack(chan, props.delivery_tag)
    ReplyRouter.route_reply(correlation_id, payload)
  end

  defp get_correlation_id(props = %{headers: headers}) do
    get_header_value(props, "x-correlation-id")
  end

  defp get_header_value(%{headers: headers}, name) do
    headers |> Enum.find(match_header(name)) |> elem(2)
  end

  defp match_header(name) do
    fn
      {^name, _, _} -> true
      _ -> false
    end
  end

end
