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
    url = Keyword.get(opts, :url)
    name = Keyword.get(opts, :name, "NoName")
    parent_pid = Keyword.get(opts, :parent_pid, nil)
    send(self(), {:connect, url, _intent = 0})
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
  def handle_info({:connect, url, intent}, state) when intent < @max_intents do
    case Connection.open(url) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        notify_connection(state, conn)
        {:noreply, %{state | connection: conn}}

      {:error, _} ->
        Logger.error("Failed to connect #{url}. Reconnecting later, intent: #{intent}...")
        Process.send_after(self(), {:connect, url, intent + 1}, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:connect, url, _}, state) do
    Logger.error("Failed to connect #{url}. Max retries reached!. Terminating!")
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

end
