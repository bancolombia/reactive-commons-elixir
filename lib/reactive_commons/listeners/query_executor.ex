defmodule QueryExecutor do
  @moduledoc false
  use GenericExecutor, type: :query

  @impl true
  def decode(%MessageToHandle{payload: payload}) do
    %{"queryData" => decoded_payload} = Poison.decode!(payload)
    decoded_payload
  end

  @impl true
  def on_post_process(resp, %MessageToHandle{headers: headers}, broker) do
    correlation_id = HeaderExtractor.get_header_value(headers, MessageHeaders.h_correlation_id())
    # TODO: habilitar header de señalización de respuesta vacía
    msg =
      OutMessage.new(
        headers: build_headers(broker, correlation_id),
        exchange_name: MessageContext.reply_exchange_name(broker),
        routing_key: HeaderExtractor.get_header_value(headers, MessageHeaders.h_reply_id()),
        payload: Poison.encode!(resp)
      )

    # TODO: considerar relacion de canal y ¿publisher confirms?
    MessageSender.send_message(msg, broker)
  end

  @impl true
  def get_handler_path(%{headers: headers}, _) do
    headers |> HeaderExtractor.get_header_value(MessageHeaders.h_served_query_id())
  end

  defp build_headers(broker, correlation_id) do
    [
      {MessageHeaders.h_correlation_id(), :longstr, correlation_id},
      {MessageHeaders.h_source_application(), :longstr,
       MessageContext.config(broker).application_name}
    ]
  end
end
