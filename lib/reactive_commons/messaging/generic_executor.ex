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
  @callback get_handler_path(MessageToHandle.t(), parsed_payload()) :: String.t()

  @doc """
  Decode message payload from MessageToHandle.
  """
  @callback decode(MessageToHandle.t()) :: parsed_payload()

  @doc """
  It's called when handler return (optional).
  """
  @callback on_post_process(handler_response(), MessageToHandle.t()) :: any()

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)
      @behaviour unquote(__MODULE__)
      @message_type unquote(opts[:type])

      def handle_message(
            msg = %MessageToHandle{delivery_tag: tag, chan: chan, handlers_ref: table}
          ) do
        t0 = :erlang.monotonic_time()

        report_to_telemetry(msg)

        try do
          event = decode(msg)
          handler_path = get_handler_path(msg, event)
          [{_path, handler_fn}] = :ets.lookup(table, handler_path)
          handler_result = handler_fn.(event)
          on_post_process(handler_result, msg)
          report_to_telemetry(msg, @message_type, handler_path, calc_duration(t0), :success)
          :ok = ack(chan, tag)
        catch
          info, error ->
            duration = calc_duration(t0)
            error_info = {info, error, duration, __STACKTRACE__}
            report_error_to_telemetry(msg, duration)
            requeue_or_ack(msg, error_info, @message_type)
        end
      end

      defp report_error_to_telemetry(msg, duration) do
        spawn(fn ->
          handler_path =
            try do
              get_handler_path(msg, decode(msg))
            catch
              _type, _err -> :erlang.atom_to_binary(@message_type) <> ".unknown"
            end

          report_to_telemetry(msg, @message_type, handler_path, duration, :failure)
        end)
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

  def requeue_or_ack(
        msg = %MessageToHandle{
          headers: headers,
          chan: chan,
          delivery_tag: tag,
          redelivered: redelivered
        },
        error_info,
        msg_type
      ) do
    num = HeaderExtractor.get_x_death_count(headers)
    is_redelivered = redelivered || num > 0
    send_error_to_custom_reporter(msg, msg_type, error_info, is_redelivered)

    if is_redelivered && MessageContext.with_dlq_retry() do
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

  defp send_error_to_custom_reporter(msg, type, {info, error, time, trace}, redelivered) do
    :telemetry.execute(
      [:async, type, :failure],
      %{duration: time},
      %{message: msg, type: info, error: error, trace: trace, redelivered: redelivered}
    )
  end

  def report_to_telemetry(msg, type, handler_path, duration, result)
      when result in [:success, :failure] do
    type_str = :erlang.atom_to_binary(type)
    transaction = "#{type_str}.#{handler_path}"

    :telemetry.execute(
      [:async, :message, :completed],
      %{duration: duration},
      %{msg: msg, transaction: transaction, result: :erlang.atom_to_binary(result)}
    )
  end

  def report_to_telemetry(msg) do
    :telemetry.execute([:async, :message, :start], %{}, %{msg: msg})
  end

  def calc_duration(t0) do
    t1 = :erlang.monotonic_time()
    :erlang.convert_time_unit(t1 - t0, :native, :microsecond)
  end

  defp log_error(msg, {info, error, _, stacktrace}, type) do
    Logger.error("Error while processing message #{inspect(info)}: #{inspect(error)}")
    Logger.error(Exception.format(info, error, stacktrace))
    Logger.warning("Message info: #{inspect(msg)}")
    type_message(type)
  end

  defp type_message(:definitive_discard), do: Logger.warning(@discard_message)
  defp type_message(:retry_dlq), do: Logger.warning(@dlq_message)
  defp type_message(:fast_retry), do: Logger.warning(@fast_retry_message)
end
