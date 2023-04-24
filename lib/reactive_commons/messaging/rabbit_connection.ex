defmodule RabbitConnection do
  use GenServer
  require Logger
  alias AMQP.Connection

  @reconnect_interval 5_000
  @max_intents 5

  defstruct [:name, :connection, :parent_pid]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    connection_props = Keyword.get(opts, :connection_props)
    name = Keyword.get(opts, :name, "NoName")
    parent_pid = Keyword.get(opts, :parent_pid, nil)
    send(self(), {:connect, connection_props, _intent = 0})
    {:ok, %__MODULE__{name: name, parent_pid: parent_pid}}
  end

  def get_connection(pid) do
    case GenServer.call(pid, :get_connection) do
      nil -> {:error, :not_connected}
      conn -> {:ok, conn}
    end
  end

  @impl true
  def handle_call(:get_connection, _from, state) do
    {:reply, state.connection, state}
  end

  @impl true
  def handle_info({:connect, connection_props, intent}, state) when intent < @max_intents do
    case Connection.open(connection_props) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        notify_connection(state, conn)
        {:noreply, %{state | connection: conn}}

      {:error, _} ->
        Logger.error("Failed to connect #{log_securely(connection_props)}. Reconnecting later, intent: #{intent}...")
        Process.send_after(self(), {:connect, connection_props, intent + 1}, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:connect, connection_props, _}, state) do
    Logger.error("Failed to connect #{log_securely(connection_props)}. Max retries reached!. Terminating!")
    {:stop, :max_reconnect_failed, state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.warning("RabbitMQ Connection Lost: #{inspect(reason)}")
    {:stop, {:connection_lost, reason}, nil}
  end

  defp notify_connection(%{parent_pid: nil}, _conn), do: :ok
  defp notify_connection(%{parent_pid: parent_pid, name: name}, conn) do
    send(parent_pid, {:connected, name, conn})
  end

  defp log_securely(connection_props) when is_binary(connection_props) do
    %URI{
      host: host,
      port: port
    } = URI.parse(connection_props)
    "host:#{host}\nport#{port}"
  end

  defp log_securely(connection_props) when is_list(connection_props) do
    Key
    "host:#{Keyword.get(connection_props, :host)}\nport#{Keyword.get(connection_props, :port)}"
  end

end
