defmodule QueryExecutor do

  require Logger

  def handle_message(msg = %MessageToHandle{delivery_tag: tag, payload: payload, headers: headers, chan: chan, handlers_ref: table}) do
    try do
      handler_path = get_handler_path(headers)
      [{_path, handler_fn}] = :ets.lookup(table, handler_path)
      %{"queryData" => decoded_payload} = Poison.decode!(payload)
      resp = handler_fn.(decoded_payload)
      send_response(resp, headers)
      :ok = AMQP.Basic.ack(chan, tag)
    catch
      info, error ->
        Logger.error("Error encounter while processing message #{inspect(info)}: #{inspect(error)}")
        Logger.warn("Message info: #{inspect(msg)}")
        Process.sleep(200)
        :ok = AMQP.Basic.reject(chan, tag)
    end
  end

  defp send_response(resp, headers) do
    correlation_id = get_header_value(headers, MessageHeaders.h_CORRELATION_ID)
    #TODO: habilitar header de señalización de respuesta vacía
    msg = OutMessage.new(
      headers: build_headers(correlation_id),
      exchange_name: MessageContext.reply_exchange_name,
      routing_key: get_header_value(headers, MessageHeaders.h_REPLY_ID),
      payload: Poison.encode!(resp)
    )
    MessageSender.send_message(msg) #TODO: considerar relacion de canal y ¿publisher confirms?
  end

  def build_headers(correlation_id) do
    [
      {MessageHeaders.h_CORRELATION_ID, :longstr, correlation_id},
      {MessageHeaders.h_SOURCE_APPLICATION, :longstr, MessageContext.config().application_name},
    ]
  end

  def get_handler_path(headers) do
    headers |> get_header_value(MessageHeaders.h_SERVED_QUERY_ID)
  end

  defp get_header_value(headers, name) do
    headers |> Enum.find(match_header(name)) |> elem(2)
  end

  defp match_header(name) do
    fn
      {^name, _, _} -> true
      _ -> false
    end
  end

end
