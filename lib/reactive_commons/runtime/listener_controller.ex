defmodule ListenerController do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, _pid} = DynamicSupervisor.start_link(strategy: :one_for_one, name: ListenerController.Supervisor)
    {:ok, %{}}
  end

  def configure(config = %HandlersConfig{}) do
    GenServer.call(__MODULE__, {:configure_handlers, config})
  end

  @impl true
  def handle_call({:configure_handlers, conf = %HandlersConfig{}}, _from, state) do
    Logger.info "Configuring handlers and starting listeners"
    MessageContext.save_handlers_config(conf)
    DynamicSupervisor.start_child(ListenerController.Supervisor, transient(QueryListener))
    DynamicSupervisor.start_child(ListenerController.Supervisor, transient(EventListener))
    DynamicSupervisor.start_child(ListenerController.Supervisor, transient(NotificationEventListener))
    DynamicSupervisor.start_child(ListenerController.Supervisor, transient(CommandListener))
    {:reply, :ok, state}
  end

  defp transient(module), do: Supervisor.child_spec({module, []}, restart: :transient)

end
