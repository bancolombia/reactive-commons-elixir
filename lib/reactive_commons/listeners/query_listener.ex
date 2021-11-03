defmodule QueryListener do
  use GenServer
  require Logger

  @handlers_table_name :query_handlers

  defstruct [:conn, :queue_name, :chan, :consumer_tag, :prefetch_count]

  def start_link(_) do
    GenServer.start_link(__MODULE__, {MessageContext.query_queue_name(), MessageContext.prefetch_count()})
  end

  @impl true
  def init({queue, prefetch_count}) do
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, %__MODULE__{queue_name: queue, prefetch_count: prefetch_count}}
  end

  @impl true
  def handle_info({:connected, conn}, state = %{queue_name: queue_name, prefetch_count: prefetch_count}) do
    {:ok, chan} = AMQP.Channel.open(conn)
    :ok = AMQP.Basic.qos(chan, prefetch_count: prefetch_count)
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue_name)
    {:noreply, %{state | chan: chan, consumer_tag: consumer_tag, conn: conn}}
  end

  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Query listener registered with consumer tag: #{inspect(consumer_tag)}")
    {:noreply, %{state | consumer_tag: consumer_tag}}
  end

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.error("Query listener consumer stoped by the broker: #{consumer_tag}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, state) do
    Logger.warn("Query listener consumer cancelled!")
    {:noreply, state}
  end

  @impl true
  def handle_info({:basic_deliver, payload, props = %{delivery_tag: _tag, redelivered: _}}, state = %{chan: _chan}) do
    consume(props, payload, state)
    {:noreply, state}
  end

  def consume(props = %{delivery_tag: _tag, redelivered: _}, payload, _state = %{chan: chan}) do
    message_to_handle = MessageToHandle.new(props, payload, chan, @handlers_table_name)
    spawn_link(QueryExecutor, :handle_message, [message_to_handle])
  end


end
