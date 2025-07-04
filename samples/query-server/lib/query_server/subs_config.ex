defmodule QueryServer.SubsConfig do
  use GenServer

  @query_name "GetPerson"
  @command_name "RegisterPerson"
  @event_name "PersonRegistered"
  @notification_event_name "ConfigurationChanged"

  def start_link(broker) do
    GenServer.start_link(__MODULE__, broker, name: :"query_server_subconfig_#{broker}")
  end

  @impl true
  def init(broker) do
    HandlerRegistry.serve_query(broker, @query_name, fn query -> get_person(query, broker) end)
    |> HandlerRegistry.handle_command(@command_name, fn command ->
      register_person(command, broker)
    end)
    |> HandlerRegistry.listen_event(@event_name, fn event ->
      person_registered(event, broker)
    end)
    |> HandlerRegistry.listen_notification_event(@notification_event_name, fn notification ->
      configuration_changed(notification, broker)
    end)
    |> HandlerRegistry.commit_config()

    {:ok, nil}
  end

  def get_person(%{} = request, broker) do
    IO.puts("Handling async query #{inspect(request)} in broker #{broker}")
    Process.sleep(150)
    Person.new_sample()
  end

  def register_person(%{} = command, broker) do
    IO.puts("Handling command #{inspect(command)} in broker #{broker}")
    event = DomainEvent.new(@event_name, PersonRegistered.new_sample(command["data"]))
    Process.sleep(150)
    :ok = DomainEventBus.emit(broker, event)
  end

  def person_registered(%{} = event, broker) do
    IO.puts("Handling event #{inspect(event)} in broker #{broker}")
    Process.sleep(5000)
    IO.puts("Handling event ends")
  end

  def configuration_changed(%{} = event, broker) do
    IO.puts("Handling notification event #{inspect(event)} in broker #{broker}")
    Process.sleep(5000)
    IO.puts("Handling notification event ends")
  end
end

defmodule Person do
  defstruct [:name, :doc, :type]

  def new_sample do
    %__MODULE__{name: "Daniel", doc: "1234", type: "Principal"}
  end
end

defmodule PersonRegistered do
  defstruct [:person, :registered_at]

  def new_sample(person) do
    %__MODULE__{person: person, registered_at: :os.system_time(:millisecond)}
  end
end
