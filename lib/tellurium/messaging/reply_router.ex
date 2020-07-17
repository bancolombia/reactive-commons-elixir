defmodule ReplyRouter do
  use GenServer

  @table_name :reply_registry

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table_name, [:named_table, read_concurrency: true])
    {:ok, nil}
  end

  def register_reply_route(correlation_id, pid) do
    GenServer.call(__MODULE__, {:register, correlation_id, pid})
  end

  def delete_reply_route(correlation_id) do
    GenServer.cast(__MODULE__, {:delete, correlation_id})
  end

  def route_reply(correlation_id, reply_message) do
    case :ets.lookup(@table_name, correlation_id) do
      [{^correlation_id, pid}] ->
        send(pid, {:reply, correlation_id, reply_message})
        delete_reply_route(correlation_id)
        :ok
      [] -> :no_route
    end
  end

  def handle_call({:register, correlation_id, pid}, _, _) do
    :ets.insert(@table_name, {correlation_id, pid})
    {:reply, :ok, nil}
  end

  def handle_cast({:delete, correlation_id}, _) do
    :ets.delete(@table_name, correlation_id)
    {:noreply, nil}
  end

end
