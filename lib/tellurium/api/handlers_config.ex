defmodule HandlersConfig do

  defstruct [
    query_listeners: %{},
    event_listeners: %{},
    command_listeners: %{}
  ]

  def new() do
    %__MODULE__{}
  end

  def add_listener(conf = %__MODULE__{}, type, path, handler) do
    Map.update!(conf, type, fn listeners -> Map.put(listeners, path, handler) end)
  end

end
