defmodule QueryListenerTest do
  use ExUnit.Case
  import Mock

  alias QueryListener

  describe "should_listen/1" do
    test "returns true when broker has handlers" do
      broker = :test_broker
      handlers = [:handler1, :handler2]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{query_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> true end do
          assert QueryListener.should_listen(broker) == true

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end

    test "returns false when broker has no handlers" do
      broker = :test_broker
      handlers = []

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{query_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> false end do
          assert QueryListener.should_listen(broker) == false

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end
  end

  describe "get_handlers/1" do
    test "returns query listeners from message context" do
      broker = :test_broker
      expected_handlers = [:handler1, :handler2, :handler3]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{query_listeners: expected_handlers} end do
        result = QueryListener.get_handlers(broker)

        assert result == expected_handlers
        assert_called(MessageContext.handlers(broker))
      end
    end

    test "returns empty list when no query listeners configured" do
      broker = :test_broker

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{query_listeners: []} end do
        result = QueryListener.get_handlers(broker)

        assert result == []
        assert_called(MessageContext.handlers(broker))
      end
    end
  end

  describe "initial_state/1" do
    test "returns correct initial state with all required fields" do
      broker = :test_broker
      queue_name = "test.query.queue"
      prefetch_count = 10

      with_mock MessageContext, [:passthrough],
        query_queue_name: fn ^broker -> queue_name end,
        prefetch_count: fn ^broker -> prefetch_count end do
        result = QueryListener.initial_state(broker)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker
        }

        assert result == expected_state
        assert_called(MessageContext.query_queue_name(broker))
        assert_called(MessageContext.prefetch_count(broker))
      end
    end
  end

  describe "create_topology/2" do
    setup do
      chan = :test_channel
      broker = :test_broker

      state = %{
        broker: broker,
        prefetch_count: 5,
        queue_name: "test.query.queue"
      }

      %{chan: chan, state: state, broker: broker}
    end

    test "creates topology without DLQ when DLQ retry is disabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      direct_exchange = "test.exchange"
      query_queue = "test.query.queue"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           query_queue_name: fn ^broker -> query_queue end,
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
        result = QueryListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))

        assert_called(AMQP.Queue.declare(chan, query_queue, durable: true))

        assert_called(
          AMQP.Queue.bind(chan, query_queue, direct_exchange, routing_key: query_queue)
        )

        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.query_queue_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
      end
    end

    test "creates topology with DLQ when DLQ retry is enabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      direct_exchange = "test.exchange"
      query_queue = "test.query.queue"
      retry_delay = 5000

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           query_queue_name: fn ^broker -> query_queue end,
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
        result = QueryListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))

        assert_called(
          AMQP.Exchange.declare(chan, direct_exchange <> ".DLQ", :direct, durable: true)
        )

        expected_args = [{"x-dead-letter-exchange", :longstr, direct_exchange <> ".DLQ"}]

        assert_called(
          AMQP.Queue.declare(chan, query_queue, durable: true, arguments: expected_args)
        )

        assert_called(
          AMQP.Queue.bind(chan, query_queue <> ".DLQ", direct_exchange <> ".DLQ",
            routing_key: query_queue
          )
        )

        assert_called(
          AMQP.Queue.bind(chan, query_queue, direct_exchange, routing_key: query_queue)
        )

        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.query_queue_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
        assert_called(MessageContext.retry_delay(broker))
      end
    end

    test "handles AMQP errors gracefully", %{chan: chan, state: state, broker: broker} do
      direct_exchange = "test.exchange"
      query_queue = "test.query.queue"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           direct_exchange_name: fn ^broker -> direct_exchange end,
           query_queue_name: fn ^broker -> query_queue end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> {:error, :channel_closed} end
         ]}
      ]) do
        assert_raise MatchError, fn ->
          QueryListener.create_topology(chan, state)
        end

        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))
      end
    end
  end

  describe "integration tests" do
    test "complete workflow from should_listen to create_topology" do
      broker = :integration_test_broker
      chan = :test_channel
      handlers = [:handler1]
      queue_name = "integration.query.queue"
      prefetch_count = 15
      direct_exchange = "integration.exchange"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           handlers: fn ^broker -> %{query_listeners: handlers} end,
           query_queue_name: fn ^broker -> queue_name end,
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
        assert QueryListener.should_listen(broker) == true

        assert QueryListener.get_handlers(broker) == handlers

        state = QueryListener.initial_state(broker)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker
        }

        assert state == expected_state

        result = QueryListener.create_topology(chan, state)
        assert result == {:ok, state}

        assert_called(MessageContext.handlers(broker))
        assert_called(ListenersValidator.has_handlers(handlers))
        assert_called(MessageContext.query_queue_name(broker))
        assert_called(MessageContext.prefetch_count(broker))
        assert_called(MessageContext.direct_exchange_name(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
        assert_called(AMQP.Exchange.declare(chan, direct_exchange, :direct, durable: true))
        assert_called(AMQP.Queue.declare(chan, queue_name, durable: true))
        assert_called(AMQP.Queue.bind(chan, queue_name, direct_exchange, routing_key: queue_name))
      end
    end
  end
end
