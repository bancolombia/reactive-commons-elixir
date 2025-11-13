defmodule RabbitConnection do
  @moduledoc false
  use GenServer
  require Logger
  alias AMQP.Connection

  @reconnect_interval 5_000
  @max_intents 5

  defstruct [:name, :connection, :parent_pid, :opts]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name)
    parent_pid = Keyword.get(opts, :parent_pid, nil)
    send(self(), {:connect, _intent = 0})
    {:ok, %__MODULE__{name: name, parent_pid: parent_pid, opts: opts}}
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
  def handle_info({:connect, intent}, state = %{opts: opts}) when intent < @max_intents do
    connection_props = Keyword.get(opts, :connection_props)
    name = Keyword.get(opts, :name, :none)

    case connect(connection_props, Atom.to_string(name)) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        notify_connection(state, conn)
        {:noreply, %{state | connection: conn}}

      {:error, reason} ->
        Logger.error(
          "Failed to connect #{log_securely(connection_props)}. Reconnecting later, intent: #{intent}..."
        )

        Logger.error("Reason: #{log_reason(reason)}")
        Process.send_after(self(), {:connect, intent + 1}, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:connect, _}, state = %{opts: opts}) do
    connection_props = Keyword.get(opts, :connection_props)

    Logger.error(
      "Failed to connect #{log_securely(connection_props)}. Max retries reached!. Terminating!"
    )

    {:stop, :max_reconnect_failed, state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.warning("RabbitMQ Connection Lost: #{inspect(reason)}")
    {:stop, {:connection_lost, reason}, nil}
  end

  def log_reason(reason = {:server_sent_malformed_header, <<21, 3, 3, 0, 2, 2, 10>>}) do
    "#{inspect(reason)} -> The server closed the connection because it requires a TLS connection. Please check your RabbitMQ connection properties and pass ssl_options."
  end

  def log_reason(reason), do: inspect(reason)

  defp connect(connection_props, name) when is_binary(connection_props) do
    Connection.open(connection_props, name: name)
  end

  defp connect(connection_props, name) do
    Connection.open(Keyword.put(connection_props, :name, name))
  end

  defp notify_connection(%{parent_pid: nil}, _conn), do: :ok

  defp notify_connection(%{parent_pid: parent_pid, name: name}, conn) do
    send(parent_pid, {:connected, name, conn})
  end

  defp log_securely(connection_props) when is_binary(connection_props) do
    %URI{host: host, port: port} = URI.parse(connection_props)
    "host: #{host}\nport: #{port}"
  end

  defp log_securely(connection_props) when is_list(connection_props) do
    "host: #{Keyword.get(connection_props, :host)}\nport: #{Keyword.get(connection_props, :port)}"
  end
end
