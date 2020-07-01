defmodule QueryClient.RestController do
  use Plug.Router
  require Logger

  @target "Receiver67"

  plug :match
  plug :dispatch


  get "/make_async_query" do
    query = AsyncQuery.new("prueba1", Person.new_sample())
    response = DirectAsyncGateway.request_reply_wait(query, @target)
    send_resp(conn, 200, "Ok")
  end

  get "/ping" do
    send_resp(conn, 200, "Pong")
  end


  def print_json(data) do
    {:ok, json} = Poison.encode(data)
    IO.puts(json)
  end

end

defmodule Person do
  defstruct [:name, :doc, :type]
  def new_sample do
    %__MODULE__{name: "Daniel", doc: "488772", type: "Principal"}
  end
end