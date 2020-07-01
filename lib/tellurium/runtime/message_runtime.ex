defmodule MessageRuntime do
  use Supervisor

  def start_link(%AsyncConfig{} = conf) do
    Supervisor.start_link(__MODULE__, conf, name: __MODULE__)
  end

  @impl true
  def init(config) do
    children = [
      {MessageContext, config},
      {ReplyRouter, []},
      {ConnectionsHolder, []},
      {ReplyListener, []},
      {MessageSender, []},
      {ListenerController, []},
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

end