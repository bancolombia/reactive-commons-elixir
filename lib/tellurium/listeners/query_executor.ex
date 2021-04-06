defmodule QueryExecutor do
  use GenericExecutor

  @impl true
  def decode(%MessageToHandle{payload: payload}) do
    %{"queryData" => decoded_payload} = Poison.decode!(payload)
    decoded_payload
  end

  @impl true
  def on_post_process(resp, %MessageToHandle{headers: headers}) do
    correlation_id = HeaderExtractor.get_header_value(headers, MessageHeaders.h_CORRELATION_ID)
    #TODO: habilitar header de señalización de respuesta vacía
    msg = OutMessage.new(
      headers: build_headers(correlation_id),
      exchange_name: MessageContext.reply_exchange_name,
      routing_key: HeaderExtractor.get_header_value(headers, MessageHeaders.h_REPLY_ID),
      payload: Poison.encode!(resp)
    )
    MessageSender.send_message(msg) #TODO: considerar relacion de canal y ¿publisher confirms?
  end

  @impl true
  def get_handler_path(%{headers: headers}, _) do
    headers |> HeaderExtractor.get_header_value(MessageHeaders.h_SERVED_QUERY_ID)
  end

  defp build_headers(correlation_id) do
    [
      {MessageHeaders.h_CORRELATION_ID, :longstr, correlation_id},
      {MessageHeaders.h_SOURCE_APPLICATION, :longstr, MessageContext.config().application_name},
    ]
  end

end
