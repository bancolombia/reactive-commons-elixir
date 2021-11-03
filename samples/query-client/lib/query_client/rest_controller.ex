defmodule QueryClient.RestController do
  use Plug.Router
  require Logger

  @target "sample-query-server"
  @query_name "GetPerson"
  @command_name "RegisterPerson"
  @event_name "PersonRegistered"

  plug :match
  plug :dispatch


  get "/query" do
    query = AsyncQuery.new(@query_name, PersonDataReq.new_sample())
    {:ok, response} = DirectAsyncGateway.request_reply_wait(query, @target)
    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json(response))
  end

  get "/command" do
    command = Command.new(@command_name, Person.new_sample())
    :ok = DirectAsyncGateway.send_command(command, @target)
    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json(command))
  end

  get "/event" do
    event = DomainEvent.new(@event_name, PersonRegistered.new_sample(Person.new_sample()))
    :ok = DomainEventBus.emit(event)
    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json(event))
  end

  get "/ping" do
    send_resp(conn, 200, "Pong")
  end

  def json(data) do
    {:ok, json} = Poison.encode(data)
    json
  end

  match _ do
    conn
    |> send_resp(404, "")
  end

end

defmodule Person do
  defstruct [:name, :doc, :type]
  def new_sample do
    %__MODULE__{name: "Daniel", doc: "1234", type: "Principal"}
  end
end

defmodule PersonDataReq do
  defstruct [:doc]
  def new_sample do
    %__MODULE__{doc: "1234"}
  end
end

defmodule PersonRegistered do
  defstruct [:person, :registered_at]
  def new_sample(person) do
    %__MODULE__{person: person, registered_at: :os.system_time(:millisecond)}
  end
end
