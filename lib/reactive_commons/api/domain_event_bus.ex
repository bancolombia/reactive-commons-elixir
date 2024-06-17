defmodule DomainEventBus do
  @moduledoc """
    This module allows the domain events emission.
  """

  def emit(event = %DomainEvent{name: name}) do
    msg =
      OutMessage.new(
        headers: headers(),
        exchange_name: MessageContext.events_exchange_name(),
        routing_key: name,
        payload: Poison.encode!(event)
      )

    case MessageSender.send_message(msg) do
      :ok -> :ok
      other -> {:emit_fail, other}
    end
  end

  def headers do
    [{MessageHeaders.h_source_application(), :longstr, MessageContext.config().application_name}]
  end
end
