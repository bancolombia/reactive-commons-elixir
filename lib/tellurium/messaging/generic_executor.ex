defmodule GenericExecutor do
  @moduledoc """
  Implements generic behaviour for message executors
  """

  import AMQP.Basic
  require Logger

  @type parsed_payload() :: map()
  @type handler_response() :: any()

  @doc """
  Extract handler function path (name) from the message.
  """
  @callback get_handler_path(MessageToHandle.t, parsed_payload()) :: String.t

  @doc """
  Decode message payload from MessageToHandle.
  """
  @callback decode(MessageToHandle.t) :: parsed_payload()

  @doc """
  It's called when handler return (optional).
  """
  @callback on_post_process(handler_response(), MessageToHandle.t()) :: any()

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      def handle_message(msg = %MessageToHandle{delivery_tag: tag, chan: chan, handlers_ref: table}) do
        t0 = :erlang.monotonic_time()
        try do
          event = decode(msg)
          handler_path = get_handler_path(msg, event)
          [{_path, handler_fn}] = :ets.lookup(table, handler_path)
          handler_result = handler_fn.(event)
          on_post_process(handler_result, msg)
          :ok = ack(chan, tag)
        catch
          info, error ->
            t1 = :erlang.monotonic_time()
            time = :erlang.convert_time_unit(t1 - t0, :native, :microsecond)
            error_info = {info, error, time, __STACKTRACE__}
            requeue_or_ack(msg, error_info)
        end
      end

      def decode(%MessageToHandle{payload: payload}) do
        Poison.decode!(payload)
      end

      def on_post_process(_, _), do: :noop

      defoverridable decode: 1, on_post_process: 2

    end
  end

  @discard_message "ATTENTION!! DEFINITIVE DISCARD!! of the message!"
  @dlq_message "ATTENTION!! Sending message to Retry DLQ"
  @fast_retry_message "ATTENTION!! Fast retry message to same Queue"

  def requeue_or_ack(msg = %MessageToHandle{headers: headers, chan: chan, delivery_tag: tag, redelivered: redelivered}, error_info) do
    num = HeaderExtractor.get_x_death_count(headers)
    is_redelivered = redelivered || num > 0
    send_error_to_custom_reporter(msg, error_info, is_redelivered)
    if is_redelivered && MessageContext.with_dlq_retry do
      if num >= MessageContext.max_retries() do
        log_error(msg, error_info, :definitive_discard)
        DiscardNotifier.notify(msg)
        :ok = ack(chan, tag)
      else
        log_error(msg, error_info, :retry_dlq)
        :ok = reject(chan, tag, requeue: false)
      end
    else
      log_error(msg, error_info, :fast_retry)
      Process.sleep(200)
      :ok = reject(chan, tag)
    end
  end

  defp send_error_to_custom_reporter(msg, {info, error, time, trace}, redelivered) do
    :telemetry.execute(
      [:async, :event, :failure],
      %{duration: time},
      %{message: msg, type: info, error: error, trace: trace, redelivered: redelivered}
    )
  end

  defp log_error(msg, {info, error, _, stacktrace}, type) do
    Logger.error("Error while processing message #{inspect(info)}: #{inspect(error)}")
    Logger.error(Exception.format(info, error, stacktrace))
    Logger.warn("Message info: #{inspect(msg)}")
    type_message(type)
  end

  defp type_message(:definitive_discard), do: Logger.warn(@discard_message)
  defp type_message(:retry_dlq), do: Logger.warn(@dlq_message)
  defp type_message(:fast_retry), do: Logger.warn(@fast_retry_message)

end

