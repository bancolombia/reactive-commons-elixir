defmodule ConnectionsHolder do
  use GenServer

  defstruct [:url, :connections, :connection_assignation]
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    url = MessageContext.config.connection_props
    connection_assignation = MessageContext.config.connection_assignation
    send(self(), :init_connections)
    {:ok, initial_state(url, connection_assignation)}
  end

  defp initial_state(url, connection_assignation) do
    connections = connection_assignation
                  |> Enum.reduce(%{}, fn {component, conn_name}, info -> add_dependent_component(info, conn_name, component) end )
    %__MODULE__{url: url, connections: connections, connection_assignation: connection_assignation}
  end

  def get_connection_async(component_name) do
    GenServer.call(__MODULE__, {:get_connection, normalize(component_name), self()})
  end

  defp normalize(component_name) do
    Atom.to_string(component_name) |> String.split(".") |> Enum.at(1) |> String.to_atom()
  end

  @impl true
  def handle_call({:get_connection, component_name, pid}, _from, state = %{connection_assignation: connection_assignation}) do
    if Map.has_key?(connection_assignation, component_name) do
      send(self(), {:send_connection, pid, component_name})
      {:reply, :ok, state}
    else
      {:reply, :no_assignation, state}
    end
  end

  @impl true
  def handle_info({:send_connection, pid, component_name}, state = %{connections: connections, connection_assignation: connection_assignation}) do
    conn_name = Map.get(connection_assignation, component_name)
    case Map.get(connections, conn_name) do
      %{conn_ref: conn_ref} -> send(pid, {:connected, conn_ref})
      _conn_info -> Process.send_after(self(), {:send_connection, pid, component_name}, 750)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:init_connections, state = %{url: url, connections: connections}) do
    Enum.each(connections, fn {conn_name, _info} -> start_connection(conn_name, url) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:connected, name, conn}, state = %{connections: connections}) do
    connections = put_conn_ref(connections, name, conn)
    {:noreply, %{state | connections: connections}}
  end

  defp put_conn_ref(connections, conn_name, conn_ref) do
    connection_info = Map.get(connections, conn_name)
    Map.put(connections, conn_name, Map.put(connection_info, :conn_ref, conn_ref))
  end

  defp start_connection(name, url), do: RabbitConnection.start_link(url: url, name: name, parent_pid: self())

  defp add_dependent_component(connections_info = %{}, conn_name, component) do
    connections_info
    |> Map.update(conn_name, %{dependent_components: [component]}, fn info -> add_in_list(info, :dependent_components, component) end)
  end

  defp add_in_list(map = %{}, path, value), do: map |> Map.put(path, [value | Map.get(map, path)])



end
