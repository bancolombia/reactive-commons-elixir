defmodule NotificationEventExecutor do
  use GenericExecutor, type: :notification_event
  def get_handler_path(%{meta: %{routing_key: routing_key}}, _), do: routing_key

end

