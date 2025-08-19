defmodule QueryServer.Application do
  @moduledoc false
  alias QueryServer.SubsConfig
  alias QueryServer.RabbitConfig

  use Application

  def start(_type, _args) do
    children = [
      {RabbitConfig, []},
      {SubsConfig, []},
    ]

    opts = [strategy: :one_for_one, name: QueryServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
