defmodule ReplyRouter do
  @moduledoc false
  use GenServer

  def start_link(broker) do
    GenServer.start_link(__MODULE__, broker, name: build_name(broker))
  end

  @impl true
  def init(broker) do
    table = table_name(broker)
    :ets.new(table, [:named_table, read_concurrency: true])
    {:ok, table}
  end

  def register_reply_route(broker, correlation_id, pid) do
    GenServer.call(build_name(broker), {:register, broker, correlation_id, pid})
  end

  def delete_reply_route(broker, correlation_id) do
    GenServer.cast(build_name(broker), {:delete, broker, correlation_id})
  end

  def route_reply(broker, correlation_id, reply_message) do
    case :ets.lookup(table_name(broker), {to_string(broker), correlation_id}) do
      [{{broker, ^correlation_id}, pid}] ->
        send(pid, {:reply, correlation_id, reply_message})
        delete_reply_route(broker, correlation_id)
        :ok

      [] ->
        :no_route
    end
  end

  @impl true
  def handle_call({:register, broker, correlation_id, pid}, _, table) do
    :ets.insert(table, {{to_string(broker), correlation_id}, pid})
    {:reply, :ok, table}
  end

  @impl true
  def handle_cast({:delete, broker, correlation_id}, table) do
    :ets.delete(table, {to_string(broker), correlation_id})
    {:noreply, table}
  end

  defp build_name(broker), do: SafeAtom.to_atom("reply_router_#{broker}")

  defp table_name(broker), do: SafeAtom.to_atom("reply_router_table_#{broker}")
end
