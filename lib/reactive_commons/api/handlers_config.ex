defmodule HandlersConfig do
  @moduledoc false
  defstruct query_listeners: %{},
            event_listeners: %{},
            notification_event_listeners: %{},
            command_listeners: %{},
            broker: :app

  @type listener_type ::
          :query_listeners | :event_listeners | :notification_event_listeners | :command_listeners

  @spec add_listener(t(), listener_type(), String.t(), any()) :: t()

  @type t :: %__MODULE__{
          query_listeners: %{String.t() => any()},
          event_listeners: %{String.t() => any()},
          notification_event_listeners: %{String.t() => any()},
          command_listeners: %{String.t() => any()},
          broker: atom()
        }

  @spec new(atom() | binary() | nil) :: t
  def new(broker) when is_binary(broker), do: %__MODULE__{broker: String.to_atom(broker)}
  def new(broker) when is_atom(broker), do: %__MODULE__{broker: broker}

  def add_listener(conf = %__MODULE__{broker: broker}, type, path, handler) do
    Map.update!(conf, type, fn listeners_by_broker ->
      Map.update(listeners_by_broker, broker, %{path => handler}, fn listeners_for_broker ->
        Map.put(listeners_for_broker, path, handler)
      end)
    end)
  end
end
