defmodule EventExecutor do
  require Logger

  def handle_message(msg = %MessageToHandle{delivery_tag: tag, payload: payload, chan: chan, handlers_ref: table}) do
    t0 = :erlang.monotonic_time()
    try do
      handler_path = get_handler_path(msg)
      [{_path, handler_fn}] = :ets.lookup(table, handler_path)
      event = Poison.decode!(payload)
      handler_fn.(event)
      :ok = AMQP.Basic.ack(chan, tag)
    catch
      info, error ->
        Logger.error("Error encounter while processing message #{inspect(info)}: #{inspect(error)}")
        Logger.warn("Message info: #{inspect(msg)}")
        t1 = :erlang.monotonic_time()
        time = :erlang.convert_time_unit(t1 - t0, :native, :microsecond)
        :telemetry.execute(
          [:async, :event, :failure],
          %{duration: time},
          %{message: msg, type: info, error: error, trace: __STACKTRACE__}
        )
        Process.sleep(200)
        :ok = AMQP.Basic.reject(chan, tag)
    end
  end

  defp get_handler_path(%{meta: %{routing_key: routing_key}}), do: routing_key

end
