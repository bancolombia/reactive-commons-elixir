defmodule ListenerController do
  use GenServer
  require Logger

  @query_handlers_table_name :query_handlers
  @command_handlers_table_name :command_handlers

  defstruct [:conn, started_listeners: false, connected: false]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ok = ConnectionsHolder.get_connection_async(__MODULE__)
    {:ok, _pid} = DynamicSupervisor.start_link(strategy: :one_for_one, name: ListenerController.Supervisor)
    :ets.new(@query_handlers_table_name, [:named_table, read_concurrency: true])
    :ets.new(@command_handlers_table_name, [:named_table, read_concurrency: true])
    {:ok, %__MODULE__{}}
  end

  def handle_info({:connected, conn}, state = %__MODULE__{}) do
    state = %__MODULE__{state | conn: conn}
    assure_basic_topology(state)
    {:noreply, %{state | connected: true}}
  end

  defp assure_basic_topology(state = %{conn: conn}) do
    {:ok, chan} = AMQP.Channel.open(conn)
    create_direct_messages_topology(chan)
    AMQP.Channel.close(chan)
    Logger.info("Basic topology assured and channel released!")
  end

  def create_direct_messages_topology(chan) do
    direct_exchange_name = MessageContext.direct_exchange_name()
    query_queue_name = MessageContext.query_queue_name()
    command_queue_name = MessageContext.command_queue_name()

    :ok = AMQP.Exchange.declare(chan, direct_exchange_name, :direct, durable: true)

    {:ok, _} = AMQP.Queue.declare(chan, query_queue_name, durable: true)
    {:ok, _} = AMQP.Queue.declare(chan, command_queue_name, durable: true)

    :ok = AMQP.Queue.bind(chan, query_queue_name, direct_exchange_name, routing_key: query_queue_name)
    :ok = AMQP.Queue.bind(chan, command_queue_name, direct_exchange_name, routing_key: command_queue_name)
  end

  def configure(config = %HandlersConfig{}) do
    GenServer.call(__MODULE__, {:configure_handlers, config})
  end

  def handle_call({:configure_handlers, %HandlersConfig{query_listeners: query_listeners, command_listeners: command_listeners}}, _from, state = %__MODULE__{}) do
    save_handlers(query_listeners, @query_handlers_table_name)
    save_handlers(command_listeners, @command_handlers_table_name)
    send(self(), :start_listeners)
    {:reply, :ok, state}
  end

  def handle_info(:start_listeners, state = %__MODULE__{}), do: {:noreply, start_listeners(state)}

  defp start_listeners(state = %__MODULE__{started_listeners: false, conn: conn, connected: true}) do
    DynamicSupervisor.start_child(ListenerController.Supervisor, QueryListener)
    #TODO: start other listeners
    Logger.info("Listeners started!")
    %{state | started_listeners: true}
  end

  defp start_listeners(state = %__MODULE__{started_listeners: true}), do: state

  defp start_listeners(state = %__MODULE__{started_listeners: false, connected: false}) do
    Logger.info("Retry start listeners in 1 seg")
    Process.send_after(self(), :start_listeners, 1000)
    state
  end

  defp save_handlers(handlers, table_name) do
    Enum.each(handlers, fn {path, handler_fn} -> :ets.insert(table_name, {path, handler_fn}) end)
  end

end
