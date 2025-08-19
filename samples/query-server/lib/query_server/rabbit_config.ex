defmodule QueryServer.RabbitConfig do
  require Logger

  use ReactiveCommonsSetup

  defp config() do
    async_config_map = Application.fetch_env!(:query_server, :async_config)
    async_config_map
  end
end
