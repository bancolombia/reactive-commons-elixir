defmodule QueryServer.SubsConfig do
  use GenServer

  @query1 "query1"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    HandlerRegistry.serve_query(@query1, &echo/1) |> HandlerRegistry.commit_config()
    {:ok, nil}
  end

  def echo(request) do
    Process.sleep(150)
    %{
      response: "OK",
      request: request
    }
  end

end
