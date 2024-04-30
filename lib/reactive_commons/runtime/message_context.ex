defmodule MessageContext do
  @moduledoc """
    This module maintain the required settings to achieve communication with the message broker, it also provides default semantic settings
  """
  use GenServer
  require Logger
  @table_name :msg_ctx

  @default_values %{
    reply_exchange: "globalReply",
    direct_exchange: "directMessages",
    events_exchange: "domainEvents",
    connection_props: "amqp://guest:guest@localhost",
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
    queries_reply: true,
    with_dlq_retry: false,
    retry_delay: 500,
    max_retries: 10,
    prefetch_count: 250
  }

  def start_link(config = %AsyncConfig{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config = %AsyncConfig{}) do
    Logger.info("Starting message context")

    config
    |> put_default_values()
    |> put_route_info()
    |> save_in_ets()

    {:ok, nil}
  end

  def save_handlers_config(config = %HandlersConfig{}) do
    GenServer.call(__MODULE__, {:save_handlers_config, config})
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

  defp save_in_ets(config) do
    :ets.new(@table_name, [:named_table, read_concurrency: true])
    :ets.insert(@table_name, {:conf, config})
  end

  def reply_queue_name, do: config().reply_queue
  def gen_reply_queue_name, do: GenServer.call(__MODULE__, {:generate_and_save, "reply"})
  def query_queue_name, do: config().query_queue
  def command_queue_name, do: config().command_queue
  def event_queue_name, do: config().event_queue
  def notification_event_queue_name, do: config().notification_event_queue

  def gen_notification_event_queue_name,
    do: GenServer.call(__MODULE__, {:generate_and_save, "notification"})

  def reply_routing_key, do: config().reply_routing_key
  def reply_exchange_name, do: config().reply_exchange
  def direct_exchange_name, do: config().direct_exchange
  def events_exchange_name, do: config().events_exchange
  def with_dlq_retry, do: config().with_dlq_retry
  def retry_delay, do: config().retry_delay
  def max_retries, do: config().max_retries
  def prefetch_count, do: config().prefetch_count
  def application_name, do: config().application_name

  def config do
    [{:conf, config}] = :ets.lookup(@table_name, :conf)
    config
  end

  def handlers_configured?, do: handlers() != []

  def handlers do
    case :ets.lookup(@table_name, :handlers) do
      [{:handlers, config}] -> config
      [] -> []
    end
  end

  @impl true
  def handle_call({:save_handlers_config, config}, _from, state) do
    Logger.info("Saving handlers config!")
    true = :ets.insert(@table_name, {:handlers, config})
    {:reply, :ok, state}
  end

  def handle_call({:generate_and_save, type}, _from, state) do
    cfg = %AsyncConfig{application_name: app_name} = config()
    generated = NameGenerator.generate(app_name, type)

    attr =
      case(type) do
        "reply" -> :reply_queue
        "notification" -> :notification_event_queue
      end

    cfg = Map.put(cfg, attr, generated)
    :ets.insert(@table_name, {:conf, cfg})
    {:reply, generated, state}
  end

  def table do
    :ets.tab2list(@table_name)
  end
end
