defmodule QueueExecutor do
  @moduledoc false
  use GenericExecutor, type: :queue_message

  @impl true
  def get_handler_path(_msj, _parsed) do
    "default"
  end

  @impl true
  def decode(msg = %MessageToHandle{payload: payload}) do
    case Poison.decode(payload) do
      {:ok, decoded} -> %MessageToHandle{msg | payload: decoded}
      {:error, _reason} -> msg
    end
  end
end
