defmodule SubsConfigProcess do
  use GenServer

  def start_link(config = %HandlersConfig{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    :ok = HandlerRegistry.commit_config(config)
    :ignore
  end
end
