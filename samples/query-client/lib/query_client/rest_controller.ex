defmodule QueryClient.RestController do
  use Plug.Router
  require Logger

  @target "sample-query-server"
  @query_path "query1"

  plug :match
  plug :dispatch


  get "/query" do
    query = AsyncQuery.new(@query_path, Person.new_sample())
    {:ok, response} = DirectAsyncGateway.request_reply_wait(query, @target)
    #send_resp(conn, 200, "Pong")
    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json(response))
  end

  get "/ping" do
    send_resp(conn, 200, "Pong")
  end

  def json(data) do
    {:ok, json} = Poison.encode(data)
    json
  end

end

defmodule Person do
  defstruct [:name, :doc, :type]
  def new_sample do
    %__MODULE__{name: "Daniel", doc: "488772", type: "Principal"}
  end
end