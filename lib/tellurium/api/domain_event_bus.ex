defmodule DomainEventBus do

  @domain_events_exchange "domainEvents"

  def emit(event = %DomainEvent{name: name}) do
    msg = OutMessage.new(
      headers: headers(),
      exchange_name: @domain_events_exchange,
      routing_key: name,
      payload: Poison.encode!(event)
    )
    case MessageSender.send_message(msg) do
      :ok -> :ok
      other -> {:emit_fail, other}
    end
  end


  def headers() do
    [{MessageHeaders.h_SOURCE_APPLICATION, :longstr, MessageContext.config().application_name}]
  end

end
