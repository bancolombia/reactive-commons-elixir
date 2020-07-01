defmodule MessageContext do
  use GenServer

  @table_name :msg_ctx

  @default_values %{
    reply_exchange: "globalReply",
    direct_exchange: "directMessages",
    connection_assignation: %{
      ReplyListener: ListenerConn,
      QueryListener: ListenerConn,
      MessageSender: SenderConn,
      ListenerController: SenderConn,
    }
  }

  def start_link(config = %AsyncConfig{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config = %AsyncConfig{}) do
    config
    |> put_default_values()
    |> put_route_info()
    |> save_in_ets()
    {:ok, nil}
  end

  defp put_route_info(config = %AsyncConfig{application_name: app_name}) do
    %AsyncConfig{config |
      reply_routing_key: NameGenerator.generate(),
      reply_queue: NameGenerator.generate(app_name),
      query_queue: "#{app_name}.query",
      command_queue: "#{app_name}",
    }
  end

  defp put_default_values(config = %AsyncConfig{}) do
    @default_values |> Enum.reduce(config, fn {key, value}, conf -> put_if_nil(conf, key, value) end)
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

  def reply_queue_name(), do: config.reply_queue
  def query_queue_name(), do: config.query_queue
  def command_queue_name(), do: config.command_queue
  def reply_routing_key(), do: config.reply_routing_key
  def reply_exchange_name(), do: config.reply_exchange
  def direct_exchange_name(), do: config.direct_exchange

  def config() do
    [{:conf, config}] = :ets.lookup(@table_name, :conf)
    config
  end


end
