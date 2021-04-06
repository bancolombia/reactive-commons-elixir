defmodule EventExecutor do
  use GenericExecutor
  def get_handler_path(%{meta: %{routing_key: routing_key}}, _), do: routing_key

end

