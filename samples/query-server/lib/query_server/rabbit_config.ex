defmodule QueryServer.RabbitConfig do
  require Logger
  alias QueryServer.SubsConfig

  use ReactiveCommonsSetup

  defp config() do
    # Here you can get secrets or any other dynamic config
    Application.fetch_env!(:query_server, :async_config)
  end

  def handlers_config(%{broker: broker}) do
    SubsConfig.config_broker(broker)
  end
end
