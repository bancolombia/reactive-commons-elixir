defmodule QueryClient.Application do
  @moduledoc false
  alias QueryClient.RestController

  use Application

  def start(_type, _args) do
    async_config_map = Application.fetch_env!(:query_client, :async_config)
    http_port = Application.fetch_env!(:query_client, :http_port)

    children = [
      {Plug.Cowboy, scheme: :http, plug: RestController, options: [port: http_port]},
      {MessageRuntime, async_config_map}
    ]

    opts = [strategy: :one_for_one, name: QueryClient.Supervisor]
    IO.puts("Listen in #{http_port}")
    Supervisor.start_link(children, opts)
  end
end
