defmodule GenericListener do
  @moduledoc """
  Implements generic behaviour for event listeners
  """

  @doc """
  Evaluate if should listen for this kind of events.
  """
  @callback should_listen() :: boolean()

  @doc """
  Get initial state.
  """
  @callback initial_state() :: map()

  @doc """
  Create resource topology.
  """
  @callback create_topology(AMQP.Channel.t()) :: atom()

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)
      use GenServer
      require Logger

      @behaviour unquote(__MODULE__)
      @kind __MODULE__
      @handlers_table unquote(opts[:handlers_table])
      @executor unquote(opts[:executor])

      defstruct [:conn, :chan, :queue_name, :consumer_tag, :prefetch_count]

      def start_link(_) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      @impl true
      def init([]) do
        IO.puts("########### STARTING #{@kind} LISTENER #############")
        if should_listen() do
          :ok = ConnectionsHolder.get_connection_async(__MODULE__)
          :ok = create_ets(@handlers_table)
          {:ok, struct(__MODULE__, initial_state())}
        else
          IO.puts("########### #{@kind} LISTENER SKIPPED #############")
          :ignore
        end
      end

      @impl true
      def handle_info({:connected, conn}, state = %{queue_name: queue_name, prefetch_count: prefetch_count}) do
        {:ok, chan} = AMQP.Channel.open(conn)
        :ok = create_topology(chan)
        :ok = AMQP.Basic.qos(chan, prefetch_count: prefetch_count)
        {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue_name)
        IO.puts("########### #{@kind} LISTENER STARTED #############")
        {:noreply, %{state | chan: chan, consumer_tag: consumer_tag, conn: conn}}
      end

      def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state = %{queue_name: queue}) do
        Logger.info("#{@kind} listener registered with consumer #{inspect(consumer_tag)} for queue #{queue}")
        {:noreply, %{state | consumer_tag: consumer_tag}}
      end

      def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state = %{queue_name: queue}) do
        Logger.error("#{@kind} listener consumer #{inspect(consumer_tag)} stopped by the broker for queue #{queue}")
        {:stop, :normal, state}
      end

      def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state = %{queue_name: queue}) do
        Logger.warn("#{@kind} listener consumer #{inspect(consumer_tag)} cancelled for queue #{queue}")
        {:noreply, state}
      end

      def handle_info({:basic_deliver, payload, props = %{delivery_tag: _tag}}, state) do
        consume(props, payload, state)
        {:noreply, state}
      end

      @impl true
      def handle_cast({:save_handlers, handlers = %{}}, state) do
        :ok = save_handlers(handlers)
        {:noreply, state}
      end

      def consume(props = %{delivery_tag: _, redelivered: _}, payload, _state = %{chan: chan}) do
        message_to_handle = MessageToHandle.new(props, payload, chan, @handlers_table)
        spawn_link(@executor, :handle_message, [message_to_handle])
      end

      def get_handlers(), do: %{}

      defp save_handlers(handlers) do
        Enum.each(handlers, fn {path, handler_fn} -> :ets.insert(@handlers_table, {path, handler_fn}) end)
      end

      defp create_ets(nil), do: :ok
      defp create_ets(table_name) do
        ^table_name = :ets.new(table_name, [:named_table, read_concurrency: true])
        GenServer.cast(__MODULE__, {:save_handlers, get_handlers()})
      end

      defoverridable consume: 3, get_handlers: 0

    end
  end

  def declare_dlq(chan, origin_queue, retry_target, retry_time) do
    args = [
      {"x-dead-letter-exchange", :longstr, retry_target},
      {"x-message-ttl", :signedint, retry_time},
    ]
    {:ok, _} = AMQP.Queue.declare(chan, origin_queue <> ".DLQ", durable: true, arguments: args)
  end

  def get_correlation_id(props = %{headers: _headers}) do
    get_header_value(props, "x-correlation-id")
  end

  defp get_header_value(%{headers: headers}, name) do
    headers
    |> Enum.find(match_header(name))
    |> elem(2)
  end

  defp match_header(name) do
    fn
      {^name, _, _} -> true
      _ -> false
    end
  end

end

