defmodule SubsConfigProcess do
  @moduledoc false
  use GenServer

  def start_link(config = %HandlersConfig{broker: broker}) do
    GenServer.start_link(__MODULE__, config,
      name: String.to_existing_atom("subs_config_process_#{broker}")
    )
  end

  def init(config) do
    :ok = HandlerRegistry.commit_config(config)
    :ignore
  end
end
