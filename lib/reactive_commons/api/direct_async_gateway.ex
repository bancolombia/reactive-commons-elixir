defmodule DirectAsyncGateway do
  @moduledoc """
    This module allows the commands emission and async queries requests.
  """

  def request_reply(%AsyncQuery{}, nil), do: raise("nil target")

  def request_reply(query = %AsyncQuery{}, target_name), do: request_reply(:app, query, target_name)

  def request_reply(broker, query = %AsyncQuery{}, target_name) do
    correlation_id = NameGenerator.generate()
    msg =
      OutMessage.new(
        headers: headers(broker, query, correlation_id),
        exchange_name: MessageContext.direct_exchange_name(broker),
        routing_key: target_name <> ".query",
        payload: Poison.encode!(query)
      )

    ReplyRouter.register_reply_route(broker, correlation_id, self())
    case MessageSender.send_message(msg, broker) do
      :ok ->
        {:ok, correlation_id}

      other ->
        ReplyRouter.delete_reply_route(broker, correlation_id)
        other
    end
  end

  def request_reply_wait(query = %AsyncQuery{}, target_name), do: request_reply_wait(:app, query, target_name)

  def request_reply_wait(broker, query = %AsyncQuery{}, target_name) do
    case request_reply(broker, query, target_name) do
      {:ok, correlation_id} -> wait_reply(correlation_id)
      other -> other
    end
  end

  def wait_reply(correlation_id, timeout \\ 15_000) do
    receive do
      {:reply, ^correlation_id, reply_message} -> {:ok, Poison.decode!(reply_message)}
    after
      timeout -> :timeout
    end
  end

  def send_command(%Command{}, nil), do: raise("nil target")

  def send_command(command = %Command{}, target_name), do: send_command(:app, command, target_name)

  def send_command(broker, command = %Command{}, target_name) do
    msg =
      OutMessage.new(
        headers: headers(broker),
        exchange_name: MessageContext.direct_exchange_name(broker),
        routing_key: target_name,
        payload: Poison.encode!(command)
      )

    case MessageSender.send_message(msg, broker) do
      :ok -> :ok
      other -> other
    end
  end

  def headers(broker, %AsyncQuery{resource: resource}, correlation_id) do
    [
      {MessageHeaders.h_reply_id(), :longstr, MessageContext.reply_routing_key(broker)},
      {MessageHeaders.h_served_query_id(), :longstr, resource},
      {MessageHeaders.h_correlation_id(), :longstr, correlation_id},
      {MessageHeaders.h_source_application(), :longstr, MessageContext.config(broker).application_name}
    ]
  end

  def headers(broker) do
    [
      {MessageHeaders.h_source_application(), :longstr, MessageContext.config(broker).application_name}
    ]
  end
end
