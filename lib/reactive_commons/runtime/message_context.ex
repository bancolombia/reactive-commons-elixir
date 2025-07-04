defmodule MessageContext do
  @moduledoc """
    This module maintain the required settings to achieve communication with the message broker, it also provides default semantic settings
  """
  use GenServer
  require Logger

  @default_values %{
    reply_exchange: "globalReply",
    direct_exchange: "directMessages",
    events_exchange: "domainEvents",
    connection_props: "amqp://guest:guest@localhost",
    broker: "app",
    connection_assignation: %{
      ReplyListener: ListenerConn,
      QueryListener: ListenerConn,
      CommandListener: ListenerConn,
      EventListener: ListenerConn,
      NotificationEventListener: ListenerConn,
      MessageExtractor: ListenerConn,
      MessageSender: SenderConn,
      ListenerController: SenderConn
    },
    topology: %{
      command_sender: false,
      queries_sender: false,
      events_sender: false
    },
    queries_reply: true,
    with_dlq_retry: false,
    retry_delay: 500,
    max_retries: 10,
    prefetch_count: 250
  }

  def start_link(config = %AsyncConfig{}) do
    broker = config.broker
    GenServer.start_link(__MODULE__, config, name: build_name(broker))
  end

  @impl true
  def init(config = %AsyncConfig{}) do
    broker = config.broker
    Logger.info("Starting message context for broker #{broker}")

    config
    |> put_default_values()
    |> put_route_info()
    |> save_in_ets(broker)

    {:ok, config}
  end

  def save_handlers_config(config = %HandlersConfig{}, broker) do
    GenServer.call(build_name(broker), {:save_handlers_config, config})
  end

  defp put_route_info(config = %AsyncConfig{application_name: app_name}) do
    %AsyncConfig{
      config
      | reply_routing_key: NameGenerator.generate(),
        reply_queue: NameGenerator.generate(app_name, "reply"),
        query_queue: "#{app_name}.query",
        event_queue: "#{app_name}.subsEvents",
        notification_event_queue: NameGenerator.generate(app_name, "notification"),
        command_queue: "#{app_name}"
    }
  end

  defp put_default_values(config = %AsyncConfig{}) do
    @default_values
    |> Enum.reduce(config, fn {key, value}, conf -> put_if_nil(conf, key, value) end)
  end

  defp put_if_nil(map, key, value) do
    case Map.get(map, key) do
      nil -> Map.put(map, key, value)
      _ -> map
    end
  end

  defp save_in_ets(config, broker) do
    table = ets_table_name(broker)
    :ets.new(table, [:named_table, read_concurrency: true])
    :ets.insert(table, {:conf, config})
  end

  defp ets_table_name(broker), do: SafeAtom.to_atom("msg_ctx_table_#{broker}")

  def reply_queue_name(broker), do: config(broker).reply_queue

  def gen_reply_queue_name(broker),
    do: GenServer.call(build_name(broker), {:generate_and_save, "reply", broker})

  def query_queue_name(broker), do: config(broker).query_queue
  def command_queue_name(broker), do: config(broker).command_queue
  def event_queue_name(broker), do: config(broker).event_queue

  def notification_event_queue_name(broker),
    do: config(broker).notification_event_queue

  def gen_notification_event_queue_name(broker),
    do: GenServer.call(build_name(broker), {:generate_and_save, "notification", broker})

  def reply_routing_key(broker), do: config(broker).reply_routing_key
  def reply_exchange_name(broker), do: config(broker).reply_exchange
  def direct_exchange_name(broker), do: config(broker).direct_exchange
  def events_exchange_name(broker), do: config(broker).events_exchange
  def with_dlq_retry(broker), do: config(broker).with_dlq_retry
  def retry_delay(broker), do: config(broker).retry_delay
  def max_retries(broker), do: config(broker).max_retries
  def prefetch_count(broker), do: config(broker).prefetch_count
  def application_name(broker), do: config(broker).application_name
  def topology(broker), do: config(broker).topology

  def config(broker) do
    table = ets_table_name(broker)
    [{:conf, config}] = :ets.lookup(table, :conf)
    config
  end

  def handlers_configured?(broker), do: handlers(broker) != []

  def handlers(broker) do
    table = ets_table_name(broker)

    case :ets.lookup(table, :handlers) do
      [{:handlers, config}] -> config
      [] -> []
    end
  end

  @impl true
  def handle_call({:save_handlers_config, config}, _from, state) do
    Logger.info("Saving handlers config for broker #{state.broker}")
    true = :ets.insert(ets_table_name(state.broker), {:handlers, config})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:generate_and_save, type, broker}, _from, state) do
    cfg = %AsyncConfig{application_name: app_name} = config(broker)
    generated = NameGenerator.generate(app_name, type)

    attr =
      case(type) do
        "reply" -> :reply_queue
        "notification" -> :notification_event_queue
      end

    cfg = Map.put(cfg, attr, generated)
    :ets.insert(ets_table_name(broker), {:conf, cfg})
    {:reply, generated, state}
  end

  def table(broker) do
    :ets.tab2list(ets_table_name(broker))
  end

  defp build_name(broker), do: SafeAtom.to_atom("msg_ctx_#{broker}")
end
