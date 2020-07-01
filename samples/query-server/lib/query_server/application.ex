defmodule QueryServer.Application do
  @moduledoc false
  alias QueryServer.SubsConfig

  use Application

  def start(_type, _args) do
    async_config = struct(AsyncConfig, Application.fetch_env!(:query_server, :async_config))
    children = [
      {MessageRuntime, async_config},
      {SubsConfig, []},
    ]

    opts = [strategy: :one_for_one, name: QueryServer.Supervisor]
    IO.puts("Start async query server: #{async_config.application_name}")
    Supervisor.start_link(children, opts)
  end

end
