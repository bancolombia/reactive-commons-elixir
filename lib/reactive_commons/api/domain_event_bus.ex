defmodule DomainEventBus do
  @moduledoc """
   This module allows the domain events emission.
  """

  def emit(event = %DomainEvent{name: _name}), do: emit(:app, event)

  def emit(broker, event = %DomainEvent{name: name}) do
    msg =
      OutMessage.new(
        headers: headers(broker),
        exchange_name: MessageContext.events_exchange_name(broker),
        routing_key: name,
        payload: Poison.encode!(event)
      )

    case MessageSender.send_message(msg, broker) do
      :ok -> :ok
      other -> {:emit_fail, other}
    end
  end

  def headers(broker) do
    [
      {MessageHeaders.h_source_application(), :longstr,
       MessageContext.config(broker).application_name}
    ]
  end
end
