defmodule ListenerController do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(broker) do
    GenServer.start_link(__MODULE__, broker, name: build_name(broker))
  end

  @impl true
  def init(broker) do
    Logger.info(
      "ListenerController: Starting dynamic supervisor for listeners in broker #{broker}"
    )

    {:ok, _pid} =
      DynamicSupervisor.start_link(strategy: :one_for_one, name: get_name(broker))

    if MessageContext.handlers_configured?(broker) do
      start_listeners(broker)
    end

    {:ok, %{broker: broker}}
  end

  def configure(config = %HandlersConfig{broker: broker}) do
    GenServer.call(build_name(broker), {:configure_handlers, config})
  end

  @impl true
  def handle_call(
        {:configure_handlers, conf = %HandlersConfig{broker: broker}},
        _from,
        state
      ) do
    Logger.info("ListenerController: Configuring handlers for broker #{broker}")
    MessageContext.save_handlers_config(conf, broker)
    start_listeners(broker)
    {:reply, :ok, state}
  end

  defp start_listeners(broker) do
    Logger.info("ListenerController: Starting listeners for broker #{broker}")
    supervisor_name = get_name(broker)
    args = %{broker: broker}
    DynamicSupervisor.start_child(supervisor_name, {QueryListener, args})
    DynamicSupervisor.start_child(supervisor_name, {EventListener, args})
    DynamicSupervisor.start_child(supervisor_name, {NotificationEventListener, args})
    DynamicSupervisor.start_child(supervisor_name, {CommandListener, args})

    Enum.each(
      QueueListener.get_childrens(broker),
      &DynamicSupervisor.start_child(supervisor_name, &1)
    )
  end

  defp build_name(broker), do: SafeAtom.to_atom("listener_controller_#{broker}")
  defp get_name(broker), do: SafeAtom.to_atom("dynamic_supervisor_#{broker}")
end
