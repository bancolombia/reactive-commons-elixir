defmodule MessageExtractor do
  use GenServer
  require Logger

  defstruct [:conn, :queue_name, :chan, :consumer_tag, messages: %{}, action: nil, message_id: nil]

  def start_link(_, opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @impl true
  def init(_) do
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, %__MODULE__{}}
  end

  def handle_info({:connected, conn}, state = %{queue_name: queue_name}) do
    {:ok, chan} = AMQP.Channel.open(conn)
    {:noreply, %{state | chan: chan, conn: conn}}
  end

  def scan_messages(queue, pid \\ __MODULE__) do
    GenServer.call(pid, {:scan_messages, queue})
  end

  def extract_message(queue, message_id, pid \\ __MODULE__) do
    GenServer.call(pid, {:extract_message, queue, message_id})
  end

  def inspect_message(queue, message_id, pid \\ __MODULE__) do
    GenServer.call(pid, {:inspect_message, queue, message_id})
  end

  def handle_call(_, _from, state = %{chan: nil}), do: {:reply, :no_connected, state}

  def handle_call({:scan_messages, queue}, _from, state = %{queue_name: nil, chan: chan}) do
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue)
    Process.send_after(self, :stop_scan, 3000)
    {:reply, :starting, %{state | queue_name: queue, consumer_tag: consumer_tag, action: :scan}}
  end

  def handle_call({:extract_message, queue, message_id}, _from, state = %{chan: chan}) do
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue)
    Process.send_after(self, :stop_extract, 3000)
    {:reply, :starting, %{state | queue_name: queue, consumer_tag: consumer_tag, action: :extract, message_id: message_id}}
  end

  def handle_call({:inspect_message, queue, message_id}, _from, state = %{chan: chan}) do
    {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue)
    Process.send_after(self, :stop_inspect, 3000)
    {:reply, :starting, %{state | queue_name: queue, consumer_tag: consumer_tag, action: :inspect, message_id: message_id}}
  end

  def handle_call({:scan_messages, queue}, _from, state), do: {:reply, :scan_already_in_progress, state}

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Query listener registered with consumer tag: #{inspect(consumer_tag)}")
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.error("Query listener consumer stoped by the broker: #{consumer_tag}")
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("Query listener consumer cancelled!")
    {:noreply, state}
  end

  def handle_info(:stop_scan, state = %{consumer_tag: consumer_tag, chan: chan, messages: messages}) do
    {:ok, _} = AMQP.Basic.cancel(chan, consumer_tag)
    IO.puts("Scan result: #{inspect(messages)}")
    {:noreply, %{state | queue_name: nil, messages: %{}, action: nil}}
  end

  def handle_info(:stop_inspect, state = %{consumer_tag: consumer_tag, chan: chan, messages: messages, action: :extract}) do
    {:ok, _} = AMQP.Basic.cancel(chan, consumer_tag)
    IO.puts("Stop Inspect!")
    {:noreply, %{state | queue_name: nil, messages: %{}, action: nil}}
  end

  def handle_info(:stop_extract, state = %{consumer_tag: consumer_tag, chan: chan, action: :extract}) do
    {:ok, _} = AMQP.Basic.cancel(chan, consumer_tag)
    IO.puts("Stop Extracting!")
    {:noreply, %{state | queue_name: nil, messages: %{}, action: nil, message_id: nil}}
  end

  def handle_info(:stop_extract, state), do: {:noreply, state}
  def handle_info(:stop_inspect, state), do: {:noreply, state}

  def handle_info({:basic_deliver, _p, %{delivery_tag: tag, message_id: message_id}}, state = %{chan: chan, messages: messages, action: :scan}) do
    :ok = AMQP.Basic.nack(chan, tag)
    {:noreply, %{state | messages: Map.update(messages, message_id, 1, &(&1 + 1))}}
  end

  def handle_info({:basic_deliver, p, %{delivery_tag: tag, message_id: message_id}}, state = %{consumer_tag: consumer_tag, chan: chan, message_id: message_id, action: :extract}) do
    :ok = AMQP.Basic.ack(chan, tag)
    {:ok, _} = AMQP.Basic.cancel(chan, consumer_tag)
    IO.puts("Extracting: #{inspect(message_id)}, payload: #{inspect(p)}")
    {:noreply, %{state | action: nil, queue_name: nil}}
  end

  def handle_info({:basic_deliver, p, props = %{delivery_tag: tag, message_id: message_id}}, state = %{consumer_tag: consumer_tag, chan: chan, message_id: message_id, action: :inspect}) do
    :ok = AMQP.Basic.nack(chan, tag)
    {:ok, _} = AMQP.Basic.cancel(chan, consumer_tag)
    IO.puts("Inspecting: #{inspect(props)}, payload: #{inspect(p)}")
    {:noreply, %{state | action: nil, queue_name: nil, message_id: nil}}
  end

  def handle_info({:basic_deliver, p, %{delivery_tag: tag, message_id: message_id}}, state = %{chan: chan, action: :extract}) do
    :ok = AMQP.Basic.nack(chan, tag)
    IO.puts("NO Extracting: #{inspect(message_id)}")
    {:noreply, state}
  end

  def handle_info({:basic_deliver, _p, %{delivery_tag: tag, message_id: message_id}}, state = %{chan: chan, messages: messages, action: nil}) do
    :ok = AMQP.Basic.nack(chan, tag)
    {:noreply, state}
  end


end
