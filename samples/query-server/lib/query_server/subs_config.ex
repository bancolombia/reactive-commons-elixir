defmodule QueryServer.SubsConfig do
  use GenServer

  @query_name "GetPerson"
  @command_name "RegisterPerson"
  @event_name "PersonRegistered"
  @notification_event_name "ConfigurationChanged"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    HandlerRegistry.serve_query(@query_name, &get_person/1)
    |> HandlerRegistry.serve_query(@query_name <> "-2", &get_person/1)
    |> HandlerRegistry.handle_command(@command_name, &register_person/1)
    |> HandlerRegistry.handle_command(@command_name <> "-2", &register_person/1)
    |> HandlerRegistry.listen_event(@event_name, &person_registered/1)
#          |> HandlerRegistry.listen_event(@event_name <> "-2", &person_registered/1)
    |> HandlerRegistry.discard_event(@event_name <> "-2")
    |> HandlerRegistry.listen_notification_event(@notification_event_name, &configuration_changed/1)
    |> HandlerRegistry.listen_notification_event(@notification_event_name <> "-2", &configuration_changed/1)
    |> HandlerRegistry.commit_config()
    {:ok, nil}
  end

  def get_person(%{} = request) do
    IO.puts "Handling async query #{inspect(request)}"
    Process.sleep(150)
    Person.new_sample()
  end

  def register_person(%{} = command) do
    IO.puts "Handling command #{inspect(command)}"
    event = DomainEvent.new(@event_name, PersonRegistered.new_sample(command["data"]))
    Process.sleep(150)
    :ok = DomainEventBus.emit(event)
  end

  def person_registered(%{} = event) do
    IO.puts "Handling event #{inspect(event)}"
    Process.sleep(5000)
    IO.puts "Handling event ends"
  end

  def configuration_changed(%{} = event) do
    IO.puts "Handling notification event #{inspect(event)}"
    Process.sleep(5000)
    IO.puts "Handling notification event ends"
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
