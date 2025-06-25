defmodule DiscardNotifier do
  @moduledoc false
  require Logger

  def notify(%MessageToHandle{payload: payload}, broker) do
    message = Poison.decode(payload)
    event = create_event(message, payload)

    case DomainEventBus.emit(broker, event) do
      :ok ->
        :ok

      error ->
        Logger.error("FATAL!! unable to notify Discard of message!! #{inspect({event, error})}")
    end
  end

  defp create_event({:ok, %{"name" => name, "data" => data, "commandId" => id}}, _) do
    DomainEvent.new(name <> ".dlq", data, id)
  end

  defp create_event({:ok, %{"name" => name, "data" => data, "eventId" => id}}, _) do
    DomainEvent.new(name <> ".dlq", data, id)
  end

  defp create_event({:ok, %{"resource" => name, "queryData" => data}}, _) do
    DomainEvent.new(name <> ".dlq", data, name <> "query")
  end

  defp create_event(decode_result, original_payload) do
    Logger.error("Unable to interpret discarded message #{inspect(decode_result)}")
    DomainEvent.new("corruptData.dlq", original_payload, "corruptData")
  end
end
