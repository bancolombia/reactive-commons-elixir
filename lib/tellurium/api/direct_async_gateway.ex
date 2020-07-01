defmodule DirectAsyncGateway do
  @direct_exchange "directMessages"


  def request_reply(query = %AsyncQuery{}, nil), do: raise("nil target")
  def request_reply(query = %AsyncQuery{}, target_name) do
    correlation_id = NameGenerator.generate()
    msg = OutMessage.new(
      headers: headers(query, correlation_id),
      exchange_name: @direct_exchange,
      routing_key: target_name <> ".query",
      payload: Poison.encode!(query)
    )
    ReplyRouter.register_reply_route(correlation_id, self())
    case MessageSender.send_message(msg) do
      :ok -> {:ok, correlation_id}
      other ->
        ReplyRouter.delete_reply_route(correlation_id)
        other
    end

  end


  def request_reply_wait(query = %AsyncQuery{}, target_name) do
    case request_reply(query, target_name) do
      {:ok, correlation_id} -> wait_reply(correlation_id)
      other -> other
    end
  end

  def wait_reply(correlation_id) do
    receive do
      {:reply, correlation_id, reply_message} -> {:ok, Poison.decode!(reply_message)}
      after 5_000 -> :timeout
    end
  end


  def headers(%AsyncQuery{resource: resource}, correlation_id) do
    [
      {MessageHeaders.h_REPLY_ID, :longstr, MessageContext.reply_routing_key()},
      {MessageHeaders.h_SERVED_QUERY_ID, :longstr, resource},
      {MessageHeaders.h_CORRELATION_ID, :longstr, correlation_id},
      {MessageHeaders.h_SOURCE_APPLICATION, :longstr, MessageContext.config().application_name},
    ]
  end

end

