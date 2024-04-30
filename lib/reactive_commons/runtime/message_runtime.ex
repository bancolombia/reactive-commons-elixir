defmodule MessageRuntime do
  @moduledoc """
    This module initializes and supervises all required processes to enable the reactive commons ecosystem
  """
  use Supervisor

  def start_link(conf = %AsyncConfig{}) do
    Supervisor.start_link(__MODULE__, conf, name: __MODULE__)
  end

  @impl true
  def init(config = %{extractor_debug: true}) do
    children = [
      {MessageContext, config},
      {ConnectionsHolder, []},
      {MessageExtractor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @impl true
  def init(config) do
    children = [
      {MessageContext, config},
      {ReplyRouter, []},
      {ConnectionsHolder, []},
      {ReplyListener, []},
      {MessageSender, []},
      {ListenerController, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
