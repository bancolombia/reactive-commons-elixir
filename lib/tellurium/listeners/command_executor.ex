defmodule CommandExecutor do
  require Logger

  def handle_message(msg = %MessageToHandle{delivery_tag: tag, payload: payload, chan: chan, handlers_ref: table}) do
    t0 = :erlang.monotonic_time()
    try do
      %{"name" => handler_path} = event = Poison.decode!(payload)
      [{_path, handler_fn}] = :ets.lookup(table, handler_path)
      handler_fn.(event)
      :ok = AMQP.Basic.ack(chan, tag)
    catch
      info, error ->
        Logger.error("Error encounter while processing message #{inspect(info)}: #{inspect(error)}")
        Logger.error(Exception.format(:error, error, __STACKTRACE__))
        Logger.warn("Message info: #{inspect(msg)}")
        t1 = :erlang.monotonic_time()
        time = :erlang.convert_time_unit(t1 - t0, :native, :microsecond)
        :telemetry.execute(
          [:async, :command, :failure],
          %{duration: time},
          %{message: msg, type: info, error: error, trace: __STACKTRACE__}
        )
        Process.sleep(200)
        :ok = AMQP.Basic.reject(chan, tag)
    end
  end

end
