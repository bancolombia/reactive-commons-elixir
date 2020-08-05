defmodule MessageSender do
  use GenServer
  require Logger

  defstruct [:chan, :conn]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, %__MODULE__{chan: nil, conn: nil}}
  end

  def send_message(message = %OutMessage{}) do
    GenServer.call(__MODULE__, message) #TODO: consider process pool usage
  end

  @impl true
  def handle_call(message = %OutMessage{}, from, state = %{chan: nil}) do
    Process.send_after(self(), {:retry, message, from, 0}, 750)
    {:noreply, state}
  end

  @impl true
  def handle_call(message = %OutMessage{headers: _, content_encoding: _}, _from, state = %{chan: chan}) do
    publish(message, chan)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:connected, conn}, _state) do
    {:ok, chan} = AMQP.Channel.open(conn)
    {:noreply, %__MODULE__{chan: chan, conn: conn}}
  end

  @impl true
  def handle_info({:retry, message = %OutMessage{}, from, count}, state = %{chan: nil}) do
    if count < 4 do
      Process.send_after(self(), {:retry, message, from, count + 1}, 750)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, message = %OutMessage{}, from, _count}, state = %{chan: chan}) do
    publish(message, chan)
    GenServer.reply(from, :ok)
    {:noreply, state}
  end

  defp publish(message = %OutMessage{headers: headers, content_encoding: encoding}, chan) do
    options = [
      headers: headers,
      content_encoding: encoding,
      content_type: message.content_type,
      persistent: message.persistent,
      timestamp: :os.system_time(:millisecond),
      message_id: UUID.uuid4(),
      app_id: MessageContext.config().application_name,
    ]
    AMQP.Basic.publish(chan, message.exchange_name, message.routing_key, message.payload, options)
  end


end

