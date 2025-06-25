defmodule ConnectionsHolder do
  @moduledoc false
  @dialyzer {:no_return, {:start_connection, 2}}

  use GenServer
  require Logger

  defstruct [:connection_props, :connections, :connection_assignation, :broker]

  def start_link(broker) do
    GenServer.start_link(__MODULE__, broker, name: build_name(broker))
  end

  @impl true
  def init(broker) do
    Logger.info("ConnectionsHolder: init for broker #{broker}")
    connection_props = MessageContext.config(broker).connection_props
    connection_assignation = MessageContext.config(broker).connection_assignation

    send(self(), :init_connections)
    {:ok, initial_state(connection_props, connection_assignation, broker)}
  end

  defp initial_state(connection_props, connection_assignation, broker) do
    connections =
      connection_assignation
      |> Enum.reduce(%{}, fn {component, conn_name}, info ->
        unique_conn_name = full_name(conn_name, broker)
        add_dependent_component(info, unique_conn_name, component)
      end)

    %__MODULE__{
      connection_props: connection_props,
      connections: connections,
      connection_assignation: connection_assignation,
      broker: broker
    }
  end

  def get_connection_async(component_name, broker) do
    GenServer.call(build_name(broker), {:get_connection, component_name, self()})
  end

  defp extract_module_from_name(component_name) do
    component_name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.drop(-1)
    |> Enum.map(&String.capitalize/1)
    |> Enum.map_join()
    |> String.to_existing_atom()
  end

  @impl true
  def handle_call({:get_connection, component_name, pid}, _from, state) do
    component = extract_module_from_name(component_name)

    if Map.has_key?(state.connection_assignation, component) do
      send(self(), {:send_connection, pid, component_name})
      {:reply, :ok, state}
    else
      {:reply, :no_assignation, state}
    end
  end

  @impl true
  def handle_info({:send_connection, pid, component_name}, state) do
    component = extract_module_from_name(component_name)
    conn_name = full_name(Map.get(state.connection_assignation, component), state.broker)

    case Map.get(state.connections, conn_name) do
      %{conn_ref: conn_ref} -> send(pid, {:connected, conn_ref})
      _conn_info -> Process.send_after(self(), {:send_connection, pid, component_name}, 750)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:init_connections, state) do
    Enum.each(state.connections, fn {conn_name, _info} ->
      start_connection(conn_name, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:connected, conn_name, conn_ref}, state) do
    connections =
      Map.update(
        state.connections,
        conn_name,
        %{conn_ref: conn_ref},
        fn info -> Map.put(info, :conn_ref, conn_ref) end
      )

    {:noreply, %{state | connections: connections}}
  end

  defp start_connection(name, state) do
    RabbitConnection.start_link(
      connection_props: state.connection_props,
      name: name,
      parent_pid: self()
    )
  end

  defp add_dependent_component(connections_info = %{}, conn_name, component) do
    Map.update(connections_info, conn_name, %{dependent_components: [component]}, fn info ->
      add_in_list(info, :dependent_components, component)
    end)
  end

  defp add_in_list(map = %{}, path, value) do
    Map.put(map, path, [value | Map.get(map, path)])
  end

  defp full_name(name, broker) do
    name
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("_" <> to_string(broker))
    |> String.to_existing_atom()
  end

  defp build_name(broker), do: String.to_existing_atom("connections_holder_#{broker}")
end
