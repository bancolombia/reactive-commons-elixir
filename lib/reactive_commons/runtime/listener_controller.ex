defmodule ListenerController do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info "ListenerController: Starting dynamic supervisor for listeners"
    {:ok, _pid} = DynamicSupervisor.start_link(strategy: :one_for_one, name: ListenerController.Supervisor)
    if MessageContext.handlers_configured?() do
      start_listeners()
    end
    {:ok, %{}}
  end

  def configure(config = %HandlersConfig{}) do
    GenServer.call(__MODULE__, {:configure_handlers, config})
  end

  @impl true
  def handle_call({:configure_handlers, conf = %HandlersConfig{}}, _from, state) do
    Logger.info "ListenerController: Configuring handlers"
    MessageContext.save_handlers_config(conf)
    start_listeners()
    {:reply, :ok, state}
  end

  defp start_listeners() do
    Logger.info "ListenerController: Starting listeners"
    DynamicSupervisor.start_child(ListenerController.Supervisor, QueryListener)
    DynamicSupervisor.start_child(ListenerController.Supervisor, EventListener)
    DynamicSupervisor.start_child(ListenerController.Supervisor, NotificationEventListener)
    DynamicSupervisor.start_child(ListenerController.Supervisor, CommandListener)
  end

end
