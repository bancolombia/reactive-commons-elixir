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
  @callback on_post_process(handler_response(), MessageToHandle.t(), String.t()) :: any()

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)
      @behaviour unquote(__MODULE__)
      @message_type unquote(opts[:type])

      @discard_message "ATTENTION!! DEFINITIVE DISCARD!! of the message!"
      @dlq_message "ATTENTION!! Sending message to Retry DLQ"
      @local_retry_message "ATTENTION!!  Message will be retried"
      require Logger

      def handle_message(
            msg = %MessageToHandle{delivery_tag: tag, chan: chan, handlers_ref: table},
            broker
          ) do
        t0 = :erlang.monotonic_time()

        report_to_telemetry(msg)

        case process_internal(msg, broker, t0, @message_type) do
          :ok ->
            :ok

          {:error, info, error, stacktrace} ->
            duration = calc_duration(t0)
            error_info = {info, error, duration, stacktrace}
            report_error_to_telemetry(msg, duration)

            case handle_invalid_message(msg, broker) do
              :handled ->
                :ok = ack(chan, tag)

              :not_handled ->
                requeue_or_ack(msg, error_info, @message_type, broker, t0)
            end
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

      defp handle_invalid_message(msg, broker) do
        case MessageContext.get_invalid_message_handler(broker) do
          nil ->
            :not_handled

          handler ->
            if handler.(@message_type, msg) == :handled do
              :handled
            else
              :not_handled
            end
        end
      end

      def decode(%MessageToHandle{payload: payload}) do
        Poison.decode!(payload)
      end

      def on_post_process(_, _, _), do: :noop

      def process_internal(
            msg = %MessageToHandle{delivery_tag: tag, chan: chan, handlers_ref: table},
            broker,
            t0,
            message_type
          ) do
        try do
          event = decode(msg)
          handler_path = get_handler_path(msg, event)
          [{_broker, handler_map}] = :ets.lookup(table, broker)
          handler_fn = Map.fetch!(handler_map, handler_path)
          handler_result = handler_fn.(event)
          on_post_process(handler_result, msg, broker)
          report_to_telemetry(msg, message_type, handler_path, calc_duration(t0), :success)
          :ok = ack(chan, tag)
        catch
          info, error -> {:error, info, error, __STACKTRACE__}
        end
      end

      def requeue_or_ack(
            msg = %MessageToHandle{
              headers: headers,
              chan: chan,
              delivery_tag: tag,
              redelivered: redelivered
            },
            error_info,
            msg_type,
            broker,
            t0
          ) do
        num = HeaderExtractor.get_x_death_count(headers)
        is_redelivered = redelivered || num > 0
        send_error_to_custom_reporter(msg, msg_type, error_info, is_redelivered)

        if MessageContext.with_dlq_retry(broker) do
          if num >= MessageContext.max_retries(broker) do
            log_error(msg, error_info, :definitive_discard)
            DiscardNotifier.notify(msg, broker)
            :ok = ack(chan, tag)
          else
            log_error(msg, error_info, :retry_dlq)
            :ok = reject(chan, tag, requeue: false)
          end
        else
          log_error(msg, error_info, :local_retry)

          local_retry(
            msg,
            msg_type,
            broker,
            t0,
            0,
            MessageContext.max_retries(broker),
            MessageContext.retry_delay(broker)
          )
        end
      end

      def local_retry(
            %MessageToHandle{
              chan: chan,
              delivery_tag: tag
            },
            _message_type,
            _broker,
            _t0,
            _attempt,
            _max_attempts = 0,
            sleep_time
          ) do
        Process.sleep(sleep_time)
        :ok = reject(chan, tag)
      end

      def local_retry(msg, message_type, broker, t0, attempt, max_attempts, sleep_time)
          when attempt < max_attempts do
        case process_internal(msg, broker, t0, message_type) do
          :ok ->
            :ok

          {:error, info, error, stacktrace} ->
            duration = calc_duration(t0)
            error_info = {info, error, duration, stacktrace}
            log_error(msg, error_info, :local_retry)
            Process.sleep(sleep_time)
            local_retry(msg, message_type, broker, t0, attempt + 1, max_attempts, sleep_time)
        end
      end

      def local_retry(msg, _message_type, _broker, _t0, _attempt, max_attempts, _sleep_time) do
        Logger.warning(
          "Local retry attempts (#{max_attempts}) exhausted for message #{inspect(msg)}"
        )

        type_message(:definitive_discard)
        :ok = ack(msg.chan, msg.delivery_tag)
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

      def log_error(msg, {info, error, _, stacktrace}, type) do
        Logger.error("Error while processing message #{inspect(info)}: #{inspect(error)}")
        Logger.error(Exception.format(info, error, stacktrace))
        Logger.warning("Message info: #{inspect(msg)}")
        type_message(type)
      end

      defp type_message(:definitive_discard), do: Logger.warning(@discard_message)
      defp type_message(:retry_dlq), do: Logger.warning(@dlq_message)
      defp type_message(:local_retry), do: Logger.warning(@local_retry_message)

      defoverridable decode: 1, on_post_process: 3
    end
  end
end
