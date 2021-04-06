defmodule ListenerController do
  use GenServer
  require Logger

  @query_handlers_table_name :query_handlers
  @event_handlers_table_name :event_handlers
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
    :ets.new(@event_handlers_table_name, [:named_table, read_concurrency: true])
    :ets.new(@command_handlers_table_name, [:named_table, read_concurrency: true])
    Process.send_after(self(), {:configure_handlers, MessageContext.handlers()}, 1000) ## OJO
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:configure_handlers, conf = %HandlersConfig{}}, _from, state = %__MODULE__{}) do
    MessageContext.save_handlers_config(conf)
    configure_handlers(conf)
    {:reply, :ok, state}
  end

  defp assure_basic_topology(_state = %{conn: conn}) do
    {:ok, chan} = AMQP.Channel.open(conn)
    create_direct_messages_topology(chan)
    AMQP.Channel.close(chan)
    Logger.info("Basic topology assured and channel released!")
  end

  defp create_direct_messages_topology(chan) do
    direct_exchange_name = MessageContext.direct_exchange_name()
    query_queue_name = MessageContext.query_queue_name()
    command_queue_name = MessageContext.command_queue_name()

    #Both cases
    :ok = AMQP.Exchange.declare(chan, direct_exchange_name, :direct, durable: true)
    #END

    if MessageContext.with_dlq_retry() do
      :ok = AMQP.Exchange.declare(chan, direct_exchange_name <> ".DLQ", :direct, durable: true)

      {:ok, _} = AMQP.Queue.declare(chan, command_queue_name, durable: true, arguments: [{"x-dead-letter-exchange", :longstr, direct_exchange_name <> ".DLQ"}])
      {:ok, _} = declare_dlq(chan, command_queue_name, direct_exchange_name, MessageContext.retry_delay())
      :ok = AMQP.Queue.bind(chan, command_queue_name <> ".DLQ", direct_exchange_name <> ".DLQ", routing_key: command_queue_name)

      {:ok, _} = AMQP.Queue.declare(chan, query_queue_name, durable: true, arguments: [{"x-dead-letter-exchange", :longstr, direct_exchange_name <> ".DLQ"}])
      {:ok, _} = declare_dlq(chan, query_queue_name, direct_exchange_name, MessageContext.retry_delay())
      :ok = AMQP.Queue.bind(chan, query_queue_name <> ".DLQ", direct_exchange_name <> ".DLQ", routing_key: query_queue_name)
    else
      {:ok, _} = AMQP.Queue.declare(chan, query_queue_name, durable: true)
      {:ok, _} = AMQP.Queue.declare(chan, command_queue_name, durable: true)
    end

    #Common post actions
    :ok = AMQP.Queue.bind(chan, command_queue_name, direct_exchange_name, routing_key: command_queue_name)
    :ok = AMQP.Queue.bind(chan, query_queue_name, direct_exchange_name, routing_key: query_queue_name)


    #Event topology
    event_queue_name = MessageContext.event_queue_name()
    events_exchange_name = MessageContext.events_exchange_name()
    app_name = MessageContext.application_name()
    retry_delay = MessageContext.retry_delay()

    #Common
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    #End Common

    if MessageContext.with_dlq_retry() do
      retry_exchange_name = "#{app_name}.#{events_exchange_name}"
      events_dlq_exchange_name = "#{retry_exchange_name}.DLQ"
      :ok = AMQP.Exchange.declare(chan, retry_exchange_name, :topic, durable: true)
      :ok = AMQP.Exchange.declare(chan, events_dlq_exchange_name, :topic, durable: true)
      declare_dlq(chan, event_queue_name, retry_exchange_name, retry_delay)
      {:ok, _} = AMQP.Queue.declare(chan, event_queue_name, durable: true, arguments: [{"x-dead-letter-exchange", :longstr, events_dlq_exchange_name}])
      :ok = AMQP.Queue.bind(chan, event_queue_name <> ".DLQ", events_dlq_exchange_name, routing_key: "#")
      :ok = AMQP.Queue.bind(chan, event_queue_name, retry_exchange_name, routing_key: "#")
    else
      {:ok, _} = AMQP.Queue.declare(chan, event_queue_name, durable: true)
    end
  end



  def configure(config = %HandlersConfig{}) do
    GenServer.call(__MODULE__, {:configure_handlers, config})
  end




  @impl true
  def handle_info(:start_listeners, state = %__MODULE__{}), do: {:noreply, start_listeners(state)}

  @impl true
  def handle_info({:connected, conn}, state = %__MODULE__{}) do
    state = %__MODULE__{state | conn: conn}
    assure_basic_topology(state)
    {:noreply, %{state | connected: true}}
  end

  @impl true
  def handle_info({:configure_handlers, conf = %HandlersConfig{}}, state = %__MODULE__{}) do
    configure_handlers(conf)
    {:noreply, state}
  end

  @impl true
  def handle_info({:configure_handlers, []}, state) do
    Logger.info("No saved state for handlers")
    {:noreply, state}
  end

  defp configure_handlers(%HandlersConfig{query_listeners: query_listeners, command_listeners: command_listeners, event_listeners: event_listeners}) do
    save_handlers(query_listeners, @query_handlers_table_name)
    save_handlers(command_listeners, @command_handlers_table_name)
    save_handlers(event_listeners, @event_handlers_table_name)
    send(self(), :start_listeners)
    IO.puts("Configuring listeners handlers 34")
  end

  defp start_listeners(state = %__MODULE__{started_listeners: false, conn: conn, connected: true}) do
    DynamicSupervisor.start_child(ListenerController.Supervisor, QueryListener)
    DynamicSupervisor.start_child(ListenerController.Supervisor, EventListener)
    DynamicSupervisor.start_child(ListenerController.Supervisor, CommandListener)
    create_event_topology(conn)
    #TODO: start other listeners
    Logger.info("Listeners started 22!")
    %{state | started_listeners: true}
  end

  defp start_listeners(state = %__MODULE__{started_listeners: true, conn: conn}) do
    create_event_topology(conn)
    state
  end

  defp start_listeners(state = %__MODULE__{started_listeners: false, connected: false}) do
    Logger.info("Retry start listeners in 1 seg")
    Process.send_after(self(), :start_listeners, 1000)
    state
  end

  defp create_event_topology(conn) do
    IO.puts "#################################"
    IO.puts "#################################"
    IO.puts "### NEW EVENT TOPOLOGY RUL2S ####"
    IO.puts "### NEW EVENT TOPOLOGY RUL2S ####"
    IO.puts "#################################"
    IO.puts "#################################"
    {:ok, chan} = AMQP.Channel.open(conn)

    event_queue_name = MessageContext.event_queue_name()
    events_exchange_name = MessageContext.events_exchange_name()


    for {event_name, _handler} <- :ets.tab2list(@event_handlers_table_name) do
      :ok = AMQP.Queue.bind(chan, event_queue_name, events_exchange_name, routing_key: event_name)
    end

    AMQP.Channel.close(chan)
    Logger.info("Event topology assured and channel released!")
  end

  defp declare_dlq(chan, origin_queue, retry_target, retry_time) do
    args = [
      {"x-dead-letter-exchange", :longstr, retry_target},
      {"x-message-ttl", :signedint, retry_time},
    ]
    {:ok, _} = AMQP.Queue.declare(chan, origin_queue <> ".DLQ", durable: true, arguments: args)
  end

  defp save_handlers(handlers, table_name) do
    Enum.each(handlers, fn {path, handler_fn} -> :ets.insert(table_name, {path, handler_fn}) end)
  end

end
