defmodule CommandListenerTest do
  use ExUnit.Case, async: true
  import Mock

  alias CommandListener
  alias MessageContext

  describe "should_listen/1" do
    test "returns true when broker has handlers" do
      broker = :test_broker
      handlers = [:handler1, :handler2]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> true end do
          assert CommandListener.should_listen(broker) == true

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end

    test "returns false when broker has no handlers" do
      broker = :test_broker
      handlers = []

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> false end do
          assert CommandListener.should_listen(broker) == false

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end

    test "handles nil handlers gracefully" do
      broker = :test_broker

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: nil} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn nil -> false end do
          assert CommandListener.should_listen(broker) == false

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(nil))
        end
      end
    end
  end

  describe "get_handlers/1" do
    test "returns command listeners from message context" do
      broker = :test_broker
      expected_handlers = [:handler1, :handler2, :handler3]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: expected_handlers} end do
        result = CommandListener.get_handlers(broker)

        assert result == expected_handlers
        assert_called(MessageContext.handlers(broker))
      end
    end

    test "returns empty list when no command listeners configured" do
      broker = :test_broker

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: []} end do
        result = CommandListener.get_handlers(broker)

        assert result == []
        assert_called(MessageContext.handlers(broker))
      end
    end

    test "returns nil when command listeners is nil" do
      broker = :test_broker

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{command_listeners: nil} end do
        result = CommandListener.get_handlers(broker)

        assert result == nil
        assert_called(MessageContext.handlers(broker))
      end
    end
  end

  describe "initial_state/1" do
    test "returns correct initial state with all required fields" do
      broker = :test_broker
      queue_name = "test.command.queue"
      prefetch_count = 5

      with_mock MessageContext, [:passthrough],
        command_queue_name: fn ^broker -> queue_name end,
        prefetch_count: fn ^broker -> prefetch_count end do
        result = CommandListener.initial_state(broker)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker
        }

        assert result == expected_state
        assert_called(MessageContext.command_queue_name(broker))
        assert_called(MessageContext.prefetch_count(broker))
      end
    end

    test "handles different broker types" do
      brokers = [:broker1, :broker2, "string_broker", 123]

      Enum.each(brokers, fn broker ->
        queue_name = "command.queue.#{broker}"
        prefetch_count = 1

        with_mock MessageContext, [:passthrough],
          command_queue_name: fn ^broker -> queue_name end,
          prefetch_count: fn ^broker -> prefetch_count end do
          result = CommandListener.initial_state(broker)

          expected_state = %{
            prefetch_count: prefetch_count,
            queue_name: queue_name,
            broker: broker
          }

          assert result == expected_state
        end
      end)
    end
  end

  describe "create_topology/2" do
    setup do
      chan = :test_channel
      broker = :test_broker

      state = %{
        broker: broker,
        prefetch_count: 5,
        queue_name: "test.command.queue"
      }

      %{chan: chan, state: state, broker: broker}
    end

    test "creates topology without DLQ when DLQ retry is disabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      direct_exchange = "test.direct.exchange"
      command_queue = "test.command.queue"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           command_queue_name: fn ^broker -> command_queue end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        result = CommandListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))

        assert_called(AMQP.Queue.declare(chan, command_queue, durable: true))

        assert_called(
          AMQP.Queue.bind(chan, command_queue, direct_exchange, routing_key: command_queue)
        )

        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.command_queue_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
      end
    end

    test "creates topology with DLQ when DLQ retry is enabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      direct_exchange = "test.direct.exchange"
      command_queue = "test.command.queue"
      retry_delay = 3000

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           command_queue_name: fn ^broker -> command_queue end,
           with_dlq_retry: fn ^broker -> true end,
           retry_delay: fn ^broker -> retry_delay end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        result = CommandListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))

        assert_called(
          AMQP.Exchange.declare(chan, direct_exchange <> ".DLQ", :direct, durable: true)
        )

        expected_args = [{"x-dead-letter-exchange", :longstr, direct_exchange <> ".DLQ"}]

        assert_called(
          AMQP.Queue.declare(chan, command_queue, durable: true, arguments: expected_args)
        )

        assert_called(
          AMQP.Queue.bind(chan, command_queue <> ".DLQ", direct_exchange <> ".DLQ",
            routing_key: command_queue
          )
        )

        assert_called(
          AMQP.Queue.bind(chan, command_queue, direct_exchange, routing_key: command_queue)
        )

        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.command_queue_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
        assert_called(MessageContext.retry_delay(broker))
      end
    end

    test "uses correct exchange type for commands", %{chan: chan, state: state, broker: broker} do
      direct_exchange = "commands.exchange"
      command_queue = "commands.queue"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           command_queue_name: fn ^broker -> command_queue end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        CommandListener.create_topology(chan, state)

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))
      end
    end

    test "uses command queue name as routing key", %{chan: chan, state: state, broker: broker} do
      direct_exchange = "test.exchange"
      command_queue = "specific.command.queue.name"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           command_queue_name: fn ^broker -> command_queue end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        CommandListener.create_topology(chan, state)

        assert_called(
          AMQP.Queue.bind(chan, command_queue, direct_exchange, routing_key: command_queue)
        )
      end
    end

    test "handles different retry delay values", %{chan: chan, state: state, broker: broker} do
      direct_exchange = "test.exchange"
      command_queue = "test.queue"
      retry_delays = [1000, 5000, 10_000, 30_000]

      Enum.each(retry_delays, fn retry_delay ->
        with_mocks([
          {MessageContext, [:passthrough],
           [
             direct_exchange_name: fn ^broker -> direct_exchange end,
             command_queue_name: fn ^broker -> command_queue end,
             with_dlq_retry: fn ^broker -> true end,
             retry_delay: fn ^broker -> retry_delay end
           ]},
          {AMQP.Exchange, [:passthrough],
           [
             declare: fn _chan, _name, _type, _opts -> :ok end
           ]},
          {AMQP.Queue, [:passthrough],
           [
             declare: fn _chan, _name, _opts -> {:ok, %{}} end,
             bind: fn _chan, _queue, _exchange, _opts -> :ok end
           ]}
        ]) do
          CommandListener.create_topology(chan, state)

          assert_called(AMQP.Exchange.declare(chan, "test.exchange", :direct, durable: true))
        end
      end)
    end
  end

  describe "error handling" do
    test "handles AMQP exchange declaration errors" do
      chan = :test_channel
      broker = :test_broker
      state = %{broker: broker, prefetch_count: 5, queue_name: "test.queue"}

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> "test.exchange" end,
           command_queue_name: fn ^broker -> "test.queue" end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> {:error, :channel_closed} end
         ]}
      ]) do
        assert_raise MatchError, fn ->
          CommandListener.create_topology(chan, state)
        end

        assert_called(AMQP.Exchange.declare(chan, "test.exchange", :direct, durable: true))
      end
    end

    test "handles AMQP queue declaration errors" do
      chan = :test_channel
      broker = :test_broker
      state = %{broker: broker, prefetch_count: 5, queue_name: "test.queue"}

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> "test.exchange" end,
           command_queue_name: fn ^broker -> "test.queue" end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:error, :queue_already_exists} end
         ]}
      ]) do
        assert_raise MatchError, fn ->
          CommandListener.create_topology(chan, state)
        end
      end
    end

    test "handles DLQ declaration errors" do
      chan = :test_channel
      broker = :test_broker
      state = %{broker: broker, prefetch_count: 5, queue_name: "test.queue"}

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> "test.exchange" end,
           command_queue_name: fn ^broker -> "test.queue" end,
           with_dlq_retry: fn ^broker -> true end,
           retry_delay: fn ^broker -> 5000 end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :error end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        assert_raise MatchError, fn ->
          CommandListener.create_topology(chan, state)
        end
      end
    end
  end

  describe "integration tests" do
    test "complete workflow from should_listen to create_topology" do
      broker = :integration_test_broker
      chan = :test_channel
      handlers = [:command_handler1, :command_handler2]
      queue_name = "integration.command.queue"
      prefetch_count = 8
      direct_exchange = "integration.commands.exchange"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           handlers: fn ^broker -> %{command_listeners: handlers} end,
           command_queue_name: fn ^broker -> queue_name end,
           prefetch_count: fn ^broker -> prefetch_count end,
           direct_exchange_name: fn ^broker -> direct_exchange end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {ListenersValidator, [:passthrough],
         [
           has_handlers: fn ^handlers -> true end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        assert CommandListener.should_listen(broker) == true

        assert CommandListener.get_handlers(broker) == handlers

        state = CommandListener.initial_state(broker)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker
        }

        assert state == expected_state

        result = CommandListener.create_topology(chan, state)
        assert result == {:ok, state}

        assert_called(MessageContext.handlers(broker))
        assert_called(ListenersValidator.has_handlers(handlers))
        assert_called(MessageContext.command_queue_name(broker))
        assert_called(MessageContext.prefetch_count(broker))
        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))
        assert_called(AMQP.Queue.declare(chan, queue_name, durable: true))
        assert_called(AMQP.Queue.bind(chan, queue_name, direct_exchange, routing_key: queue_name))
      end
    end

    test "complete workflow with DLQ enabled" do
      broker = :dlq_integration_broker
      chan = :test_channel
      handlers = [:command_handler1]
      queue_name = "dlq.integration.command.queue"
      prefetch_count = 3
      direct_exchange = "dlq.integration.commands.exchange"
      retry_delay = 7000

      with_mocks([
        {MessageContext, [:passthrough],
         [
           handlers: fn ^broker -> %{command_listeners: handlers} end,
           command_queue_name: fn ^broker -> queue_name end,
           prefetch_count: fn ^broker -> prefetch_count end,
           direct_exchange_name: fn ^broker -> direct_exchange end,
           with_dlq_retry: fn ^broker -> true end,
           retry_delay: fn ^broker -> retry_delay end
         ]},
        {ListenersValidator, [:passthrough],
         [
           has_handlers: fn ^handlers -> true end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> :ok end
         ]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _chan, _name, _opts -> {:ok, %{}} end,
           bind: fn _chan, _queue, _exchange, _opts -> :ok end
         ]}
      ]) do
        assert CommandListener.should_listen(broker) == true
        assert CommandListener.get_handlers(broker) == handlers

        state = CommandListener.initial_state(broker)
        result = CommandListener.create_topology(chan, state)
        assert result == {:ok, state}

        dlq_exchange = direct_exchange <> ".DLQ"
        expected_args = [{"x-dead-letter-exchange", :longstr, dlq_exchange}]

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))
        assert_called(AMQP.Exchange.declare(chan, dlq_exchange, :direct, durable: true))

        assert_called(
          AMQP.Queue.declare(chan, queue_name, durable: true, arguments: expected_args)
        )

        assert_called(
          AMQP.Queue.bind(chan, queue_name <> ".DLQ", dlq_exchange, routing_key: queue_name)
        )

        assert_called(AMQP.Queue.bind(chan, queue_name, direct_exchange, routing_key: queue_name))
      end
    end
  end
end
