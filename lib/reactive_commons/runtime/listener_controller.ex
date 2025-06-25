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
    DynamicSupervisor.start_child(get_name(broker), {QueryListener, broker})
    DynamicSupervisor.start_child(get_name(broker), {EventListener, broker})
    DynamicSupervisor.start_child(get_name(broker), {NotificationEventListener, broker})
    DynamicSupervisor.start_child(get_name(broker), {CommandListener, broker})
  end

  defp build_name(broker), do: String.to_existing_atom("listener_controller_#{broker}")
  defp get_name(broker), do: String.to_existing_atom("dynamic_supervisor_#{broker}")
end
