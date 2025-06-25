defmodule MessageSender do
  @moduledoc false
  use GenServer
  alias ReactiveCommons.Utils.SpanUtils
  require Logger

  defstruct [:chan, :conn, :broker]

  def start_link(broker) do
    GenServer.start_link(__MODULE__, broker, name: build_name(__MODULE__, broker))
  end

  @impl true
  def init(broker) do
    :ok = ConnectionsHolder.get_connection_async(build_name(__MODULE__, broker), broker)
    {:ok, %__MODULE__{chan: nil, conn: nil, broker: broker}}
  end

  def send_message(%OutMessage{} = message, broker) do
    GenServer.call(build_name(__MODULE__, broker), message)
  end

  @impl true
  def handle_call(%OutMessage{} = message, from, %{chan: nil} = state) do
    Process.send_after(self(), {:retry, message, from, 0}, 750)
    {:noreply, state}
  end

  @impl true
  def handle_call(%OutMessage{} = message, from, %{chan: chan, broker: broker} = state) do
    publish(message, chan, from, broker)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:connected, conn}, %{broker: broker} =state) do
    {:ok, chan} = AMQP.Channel.open(conn)
    create_topology(chan, broker)
    {:noreply, %{state | chan: chan, conn: conn}}
  end

  @impl true
  def handle_info({:retry, %OutMessage{} = message, from, count}, %{chan: nil} = state) do
    if count < 4 do
      Process.send_after(self(), {:retry, message, from, count + 1}, 750)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, %OutMessage{} = message, from, _count}, %{chan: chan, broker: broker} = state) do
    publish(message, chan, from, broker)
    GenServer.reply(from, :ok)
    {:noreply, state}
  end

  defp publish(%OutMessage{} = message, chan, from, broker) do
    options = [
      headers: SpanUtils.inject(message.headers, from),
      content_encoding: message.content_encoding,
      content_type: message.content_type,
      persistent: message.persistent,
      timestamp: :os.system_time(:millisecond),
      message_id: UUID.uuid4(),
      app_id: MessageContext.config(broker).application_name
    ]
    result =
      AMQP.Basic.publish(
        chan,
        message.exchange_name,
        message.routing_key,
        message.payload,
        options
      )
    send_telemetry(System.monotonic_time(), message, options, result, from)
    result
  end

  defp send_telemetry(start, message = %OutMessage{}, options, result, {caller, _}) do
    :telemetry.execute(
      [:async, :message, :sent],
      %{duration: System.monotonic_time() - start},
      %{
        exchange: message.exchange_name,
        routing_key: message.routing_key,
        options: options,
        result: result,
        caller: caller
      }
    )
  end

  defp create_topology(chan, broker) do
    opts = MessageContext.topology(broker)

    if opts.command_sender || opts.queries_sender do
      direct_exchange = MessageContext.direct_exchange_name(broker)
      :ok = AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true)
    end

    if opts.events_sender do
      topic_exchange = MessageContext.events_exchange_name(broker)
      :ok = AMQP.Exchange.declare(chan, topic_exchange, :topic, durable: true)
    end
  end

  defp build_name(module, broker) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("_" <> to_string(broker))
    |> String.to_atom()
  end
end