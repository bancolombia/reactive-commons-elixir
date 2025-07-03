defmodule QueryServer.Application do
  @moduledoc false
  alias QueryServer.SubsConfig

  use Application

  def start(_type, _args) do
    async_config_map = Application.fetch_env!(:query_server, :async_config)

    children =
      [
        {MessageRuntime, async_config_map}
      ] ++
        Enum.map(Map.keys(async_config_map), fn broker ->
          Supervisor.child_spec({SubsConfig, :"#{broker}"},
            id: SafeAtom.to_atom("subs_config_process_#{broker}")
          )
        end)

    opts = [strategy: :one_for_one, name: QueryServer.Supervisor]

    IO.puts(
      "Start async query server with brokers: #{Map.keys(async_config_map) |> Enum.join(", ")}"
    )

    Supervisor.start_link(children, opts)
  end
end
