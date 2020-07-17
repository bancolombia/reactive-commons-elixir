defmodule EventListener do
  use GenServer
  require Logger

  @handlers_table_name :event_handlers

  defstruct [:conn, :queue_name, :chan, :consumer_tag]

  def start_link(_) do
    GenServer.start_link(__MODULE__, MessageContext.event_queue_name())
  end

  @impl true
  def init(queue) do
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, %__MODULE__{queue_name: queue}}
  end

  def handle_info({:connected, conn}, state = %{queue_name: queue_name}) do
    {:ok, chan} = AMQP.Channel.open(conn)
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue_name)
    {:noreply, %{state | chan: chan, consumer_tag: consumer_tag, conn: conn}}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Query listener registered with consumer tag: #{inspect(consumer_tag)}")
    {:noreply, %{state | consumer_tag: consumer_tag}}
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.error("Query listener consumer stoped by the broker: #{consumer_tag}")
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("Query listener consumer cancelled!")
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, props = %{delivery_tag: tag, redelivered: redelivered}}, state = %{chan: chan}) do
    consume(props, payload, state)
    {:noreply, state}
  end

  def consume(props = %{delivery_tag: tag, redelivered: redelivered}, payload, state = %{chan: chan}) do
    message_to_handle = MessageToHandle.new(props, payload, chan, @handlers_table_name)
    spawn_link(EventExecutor, :handle_message, [message_to_handle])
  end

end
