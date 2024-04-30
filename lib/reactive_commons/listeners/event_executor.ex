defmodule EventExecutor do
  @moduledoc false
  use GenericExecutor, type: :event
  def get_handler_path(%{meta: %{routing_key: routing_key}}, _), do: routing_key
end
