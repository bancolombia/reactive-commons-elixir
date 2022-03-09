defmodule HandlersConfig do

  defstruct [
    query_listeners: %{},
    event_listeners: %{},
    notification_event_listeners: %{},
    command_listeners: %{},
    discarded_events: %{}
  ]

  def new() do
    %__MODULE__{}
  end

  def add_listener(conf = %__MODULE__{}, type, path, handler) do
    Map.update!(conf, type, fn listeners -> Map.put(listeners, path, handler) end)
  end

  def remove_listener(conf = %__MODULE__{}, path) do
    Map.update!(conf, :discarded_events, fn discarded -> Map.put(discarded, path, true) end)
  end

end
