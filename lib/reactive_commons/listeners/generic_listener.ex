defmodule GenericListener do
  @moduledoc """
  Implements generic behaviour for event listeners
  """

  @doc """
  Evaluate if should listen for this kind of events.
  """
  @callback should_listen(String.t()) :: boolean()

  @doc """
  Get initial state.
  """
  @callback initial_state(String.t(), String.t()) :: map()

  @doc """
  Create resource topology.
  """
  @callback create_topology(AMQP.Channel.t(), map()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)
      use GenServer
      require Logger

      @behaviour unquote(__MODULE__)
      @kind __MODULE__
      @executor unquote(opts[:executor])

      defstruct [:conn, :chan, :queue_name, :consumer_tag, :prefetch_count, :broker]

      def start_link(broker) do
        name = build_name(__MODULE__, broker)
        GenServer.start_link(__MODULE__, broker, name: name)
      end

      @impl true
      def init(broker) do
        IO.puts("########### STARTING #{@kind} LISTENER FOR BROKER #{broker} #############")

        if should_listen(broker) do
          component_name = build_name(__MODULE__, broker)
          :ok = ConnectionsHolder.get_connection_async(component_name, broker)
          table = table_name(broker)
          :ok = create_ets(table, broker)
          {:ok, struct(__MODULE__, initial_state(broker, table))}
        else
          IO.puts("########### #{@kind} LISTENER SKIPPED FOR BROKER #{broker} #############")
          :ignore
        end
      end

      @impl true
      def handle_info({:connected, conn}, state = %{broker: broker}) do
        {:ok, chan} = AMQP.Channel.open(conn)
        {:ok, new_state} = create_topology(chan, state)
        %{queue_name: queue_name, prefetch_count: prefetch_count} = new_state
        :ok = AMQP.Basic.qos(chan, prefetch_count: prefetch_count)
        {:ok, consumer_tag} = AMQP.Basic.consume(chan, queue_name)

        IO.puts(
          "########### #{@kind} LISTENER STARTED FOR QUEUE #{queue_name} IN BROKER #{broker} #############"
        )

        {:noreply, %{new_state | chan: chan, consumer_tag: consumer_tag, conn: conn}}
      end

      def handle_info(
            {:basic_consume_ok, %{consumer_tag: consumer_tag}},
            state = %{queue_name: queue, broker: broker}
          ) do
        Logger.info(
          "#{@kind} listener registered with consumer #{inspect(consumer_tag)} for queue #{queue} in broker #{broker}"
        )

        {:noreply, %{state | consumer_tag: consumer_tag}}
      end

      def handle_info(
            {:basic_cancel, %{consumer_tag: consumer_tag}},
            state = %{queue_name: queue, broker: broker}
          ) do
        Logger.error(
          "#{@kind} listener consumer #{inspect(consumer_tag)} stopped by the broker for queue #{queue} in broker #{broker}"
        )

        {:stop, :normal, state}
      end

      def handle_info(
            {:basic_cancel_ok, %{consumer_tag: consumer_tag}},
            state = %{queue_name: queue, broker: broker}
          ) do
        Logger.warning(
          "#{@kind} listener consumer #{inspect(consumer_tag)} cancelled for queue #{queue} in broker #{broker}"
        )

        {:noreply, state}
      end

      def handle_info({:basic_deliver, payload, props = %{delivery_tag: _tag}}, state) do
        consume(props, payload, state)
        {:noreply, state}
      end

      @impl true
      def handle_cast({:save_handlers, handlers = %{}}, state = %{table: table}) do
        :ok = save_handlers(handlers, table)
        {:noreply, state}
      end

      def consume(
            props = %{delivery_tag: _, redelivered: _},
            payload,
            state = %{chan: chan, broker: broker, table: table}
          ) do
        message_to_handle =
          MessageToHandle.new(props, payload, chan, table)

        spawn_link(@executor, :handle_message, [message_to_handle, broker])
      end

      def get_handlers(broker), do: %{}

      defp stop_and_delete(_state = %{queue_name: nil}), do: :ok
      defp stop_and_delete(_state = %{consumer_tag: nil}), do: :ok

      defp stop_and_delete(%{chan: chan, queue_name: queue_name, consumer_tag: tag}) do
        AMQP.Basic.cancel(chan, tag)
        AMQP.Queue.delete(chan, queue_name)
        Logger.info("Stopped and deleted queue #{queue_name}")
      end

      defp save_handlers(handlers, table) do
        Enum.each(
          handlers,
          fn {path, handler_fn} ->
            :ets.insert(table, {path, handler_fn})
          end
        )

        :ok
      end

      defp table_name(broker),
        do: SafeAtom.to_atom("handler_table_#{build_name(__MODULE__, broker)}")

      defp build_name(module, broker) do
        module
        |> Atom.to_string()
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
        |> Kernel.<>("_" <> to_string(broker))
        |> SafeAtom.to_atom()
      end

      defp create_ets(table_name, broker) do
        :ets.new(table_name, [:named_table, read_concurrency: true])
        GenServer.cast(build_name(__MODULE__, broker), {:save_handlers, get_handlers(broker)})
      end

      defoverridable consume: 3, get_handlers: 1
    end
  end

  def declare_dlq(chan, origin_queue, retry_target, retry_time) do
    args = [
      {"x-dead-letter-exchange", :longstr, retry_target},
      {"x-message-ttl", :signedint, retry_time}
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
