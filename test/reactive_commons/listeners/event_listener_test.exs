defmodule EventListenerTest do
  use ExUnit.Case
  import Mock

  alias EventListener

  describe "should_listen/1" do
    test "returns true when broker has handlers" do
      broker = :test_broker
      handlers = [:handler1, :handler2]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{event_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> true end do
          assert EventListener.should_listen(broker) == true

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end

    test "returns false when broker has no handlers" do
      broker = :test_broker
      handlers = []

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{event_listeners: handlers} end do
        with_mock ListenersValidator, [:passthrough], has_handlers: fn ^handlers -> false end do
          assert EventListener.should_listen(broker) == false

          assert_called(MessageContext.handlers(broker))
          assert_called(ListenersValidator.has_handlers(handlers))
        end
      end
    end
  end

  describe "get_handlers/1" do
    test "returns event listeners from message context" do
      broker = :test_broker
      expected_handlers = [:handler1, :handler2, :handler3]

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{event_listeners: expected_handlers} end do
        result = EventListener.get_handlers(broker)

        assert result == expected_handlers
        assert_called(MessageContext.handlers(broker))
      end
    end

    test "returns empty list when no event listeners configured" do
      broker = :test_broker

      with_mock MessageContext, [:passthrough], handlers: fn ^broker -> %{event_listeners: []} end do
        result = EventListener.get_handlers(broker)

        assert result == []
        assert_called(MessageContext.handlers(broker))
      end
    end
  end

  describe "initial_state/1" do
    test "returns correct initial state with all required fields" do
      broker = :test_broker
      table = :event_test_broker_table
      queue_name = "test.event.queue"
      prefetch_count = 15

      with_mock MessageContext, [:passthrough],
        event_queue_name: fn ^broker -> queue_name end,
        prefetch_count: fn ^broker -> prefetch_count end do
        result = EventListener.initial_state(broker, table)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker,
          table: table
        }

        assert result == expected_state
        assert_called(MessageContext.event_queue_name(broker))
        assert_called(MessageContext.prefetch_count(broker))
      end
    end
  end

  describe "create_topology/2" do
    setup do
      chan = :test_channel
      broker = :test_broker
      table = :"handler_table_event_listener_#{broker}"

      state = %{
        broker: broker,
        prefetch_count: 10,
        queue_name: "test.event.queue",
        table: table
      }

      :ets.new(table, [:named_table, :public])

      ets_data = [
        {:user_domain,
         [
           {"user.created", :handler1},
           {"user.updated", :handler2},
           {"user.deleted", :handler3}
         ]},
        {:order_domain,
         [
           {"order.placed", :handler4},
           {"order.cancelled", :handler5}
         ]},
        {:payment_domain,
         [
           {"payment.processed", :handler6}
         ]}
      ]

      :ets.insert(table, ets_data)

      %{chan: chan, state: state, broker: broker, table: table}
    end

    test "creates topology without DLQ when DLQ retry is disabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      app_name = "test_app"
      event_queue = "test.event.queue"
      events_exchange = "test.events.exchange"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           application_name: fn ^broker -> app_name end,
           event_queue_name: fn ^broker -> event_queue end,
           events_exchange_name: fn ^broker -> events_exchange end,
           with_dlq_retry: fn ^broker -> false end,
           retry_delay: fn ^broker -> 2 end
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
        result = EventListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert called(AMQP.Exchange.declare(chan, events_exchange, :topic, durable: true))

        assert called(AMQP.Queue.declare(chan, event_queue, durable: true))

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.created")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.updated")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "order.placed")
               )

        assert called(MessageContext.event_queue_name(broker))
        assert called(MessageContext.events_exchange_name(broker))
        assert called(MessageContext.with_dlq_retry(broker))
      end
    end

    test "creates topology with DLQ when DLQ retry is enabled", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      event_queue = "test.event.queue"
      events_exchange = "test.events.exchange"
      app_name = "test_app"
      retry_delay = 5000

      with_mocks([
        {MessageContext, [:passthrough],
         [
           event_queue_name: fn ^broker -> event_queue end,
           events_exchange_name: fn ^broker -> events_exchange end,
           application_name: fn ^broker -> app_name end,
           retry_delay: fn ^broker -> retry_delay end,
           with_dlq_retry: fn ^broker -> true end
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
        result = EventListener.create_topology(chan, state)

        assert result == {:ok, state}

        retry_exchange = "#{app_name}.#{events_exchange}"
        dlq_exchange = "#{retry_exchange}.DLQ"

        assert_called(AMQP.Exchange.declare(chan, events_exchange, :topic, durable: true))
        assert_called(AMQP.Exchange.declare(chan, retry_exchange, :topic, durable: true))
        assert_called(AMQP.Exchange.declare(chan, dlq_exchange, :topic, durable: true))

        expected_args = [{"x-dead-letter-exchange", :longstr, dlq_exchange}]

        assert_called(
          AMQP.Queue.declare(chan, event_queue, durable: true, arguments: expected_args)
        )

        assert_called(
          AMQP.Queue.bind(chan, event_queue <> ".DLQ", dlq_exchange, routing_key: "#")
        )

        assert_called(AMQP.Queue.bind(chan, event_queue, retry_exchange, routing_key: "#"))

        assert_called(
          AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.created")
        )

        assert_called(MessageContext.event_queue_name(broker))
        assert_called(MessageContext.events_exchange_name(broker))
        assert_called(MessageContext.application_name(broker))
        assert_called(MessageContext.retry_delay(broker))
        assert_called(MessageContext.with_dlq_retry(broker))
      end
    end

    test "handles empty ETS table gracefully", %{chan: chan, state: state, broker: broker} do
      app_name = "test_app"
      event_queue = "test.event.queue"
      events_exchange = "test.events.exchange"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           application_name: fn ^broker -> app_name end,
           event_queue_name: fn ^broker -> event_queue end,
           events_exchange_name: fn ^broker -> events_exchange end,
           with_dlq_retry: fn ^broker -> false end,
           retry_delay: fn ^broker -> 2 end
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
        result = EventListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert_called(AMQP.Exchange.declare(chan, events_exchange, :topic, durable: true))
        assert_called(AMQP.Queue.declare(chan, event_queue, durable: true))
      end
    end

    test "creates multiple bindings for complex ETS data", %{
      chan: chan,
      state: state,
      broker: broker
    } do
      app_name = "test_app"
      event_queue = "test.event.queue"
      events_exchange = "test.events.exchange"

      with_mocks([
        {MessageContext, [:passthrough],
         [
           application_name: fn ^broker -> app_name end,
           event_queue_name: fn ^broker -> event_queue end,
           events_exchange_name: fn ^broker -> events_exchange end,
           with_dlq_retry: fn ^broker -> false end,
           retry_delay: fn ^broker -> 2 end
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
        result = EventListener.create_topology(chan, state)

        assert result == {:ok, state}

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.created")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.updated")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "user.deleted")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange, routing_key: "order.placed")
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange,
                   routing_key: "order.cancelled"
                 )
               )

        assert called(
                 AMQP.Queue.bind(chan, event_queue, events_exchange,
                   routing_key: "payment.processed"
                 )
               )
      end
    end
  end

  describe "table/1 (private function testing through behavior)" do
    setup do
      broker = :test_broker
      table = :"handler_table_event_listener_#{broker}"
      :ets.new(table, [:named_table, :public])
      %{broker: broker, table: table}
    end

    test "generates correct table name format", %{table: table, broker: broker} do
      chan = :test_channel
      state = %{broker: broker, prefetch_count: 10, queue_name: "test.queue", table: table}

      with_mock MessageContext, [:passthrough],
        application_name: fn ^broker -> "test_app" end,
        event_queue_name: fn ^broker -> "test.queue" end,
        events_exchange_name: fn ^broker -> "test.exchange" end,
        with_dlq_retry: fn ^broker -> false end,
        retry_delay: fn ^broker -> 2 end do
        with_mock AMQP.Exchange, [:passthrough], declare: fn _, _, _, _ -> :ok end do
          with_mock AMQP.Queue, [:passthrough],
            declare: fn _, _, _ -> {:ok, %{}} end,
            bind: fn _, _, _, _ -> :ok end do
            EventListener.create_topology(chan, state)
          end
        end
      end
    end
  end

  describe "build_name/2 (private function testing through behavior)" do
    setup do
      brokers = [:broker1, :broker2, :custom_broker]

      Enum.each(brokers, fn broker ->
        table = :"handler_table_event_listener_#{broker}"
        :ets.new(table, [:named_table, :public])
        %{broker: broker, table: table}
      end)
    end

    test "generates correct module-based names for different brokers" do
      brokers = [:broker1, :broker2, :custom_broker]

      Enum.each(brokers, fn broker ->
        chan = :test_channel
        table = :"handler_table_event_listener_#{broker}"
        state = %{broker: broker, prefetch_count: 10, queue_name: "test.queue", table: table}

        with_mocks([
          {MessageContext, [:passthrough],
           [
             application_name: fn ^broker -> "test_app" end,
             event_queue_name: fn ^broker -> "test.queue" end,
             events_exchange_name: fn ^broker -> "test.exchange" end,
             with_dlq_retry: fn ^broker -> false end,
             retry_delay: fn ^broker -> 2 end
           ]},
          {AMQP.Exchange, [:passthrough], [declare: fn _, _, _, _ -> :ok end]},
          {AMQP.Queue, [:passthrough],
           [
             declare: fn _, _, _ -> {:ok, %{}} end,
             bind: fn _, _, _, _ -> :ok end
           ]}
        ]) do
          EventListener.create_topology(chan, state)
        end
      end)
    end
  end

  describe "error handling" do
    test "handles AMQP exchange declaration errors", %{} do
      chan = :test_channel
      broker = :test_broker
      state = %{broker: broker, prefetch_count: 10, queue_name: "test.queue", table: :test_table}

      with_mocks([
        {MessageContext, [:passthrough],
         [
           application_name: fn ^broker -> "test" end,
           event_queue_name: fn ^broker -> "test.queue" end,
           events_exchange_name: fn ^broker -> "test.exchange" end,
           with_dlq_retry: fn ^broker -> false end,
           retry_delay: fn ^broker -> 2 end
         ]},
        {AMQP.Exchange, [:passthrough],
         [
           declare: fn _chan, _name, _type, _opts -> {:error, :channel_closed} end
         ]}
      ]) do
        assert_raise MatchError, fn ->
          EventListener.create_topology(chan, state)
        end
      end
    end

    test "handles ETS table lookup errors", %{} do
      chan = :test_channel
      broker = :test_broker
      state = %{broker: broker, prefetch_count: 10, queue_name: "test.queue", table: :test_table}

      with_mocks([
        {MessageContext, [:passthrough],
         [
           event_queue_name: fn ^broker -> "test.queue" end,
           events_exchange_name: fn ^broker -> "test.exchange" end,
           with_dlq_retry: fn ^broker -> false end
         ]},
        {AMQP.Exchange, [:passthrough], [declare: fn _, _, _, _ -> :ok end]},
        {AMQP.Queue, [:passthrough], [declare: fn _, _, _ -> {:ok, %{}} end]}
      ]) do
        assert_raise ArgumentError, fn ->
          EventListener.create_topology(chan, state)
        end
      end
    end
  end

  describe "integration tests" do
    setup do
      broker = :integration_broker
      table_name = :"handler_table_event_listener_#{broker}"
      :ets.new(table_name, [:named_table, :public])

      ets_data = [
        {:domain1, [{"event.type1", :handler1}, {"event.type2", :handler2}]}
      ]

      :ets.insert(table_name, ets_data)
      %{broker: broker, table: table_name}
    end

    test "complete workflow with DLQ and multiple event bindings", %{broker: broker, table: table} do
      chan = :test_channel
      handlers = [:handler1, :handler2]
      queue_name = "integration.event.queue"
      prefetch_count = 20
      events_exchange = "integration.events"
      app_name = "integration_app"
      retry_delay = 3000

      with_mocks([
        {MessageContext, [:passthrough],
         [
           handlers: fn ^broker -> %{event_listeners: handlers} end,
           event_queue_name: fn ^broker -> queue_name end,
           prefetch_count: fn ^broker -> prefetch_count end,
           events_exchange_name: fn ^broker -> events_exchange end,
           application_name: fn ^broker -> app_name end,
           retry_delay: fn ^broker -> retry_delay end,
           with_dlq_retry: fn ^broker -> true end
         ]},
        {ListenersValidator, [:passthrough],
         [
           has_handlers: fn ^handlers -> true end
         ]},
        {AMQP.Exchange, [:passthrough], [declare: fn _, _, _, _ -> :ok end]},
        {AMQP.Queue, [:passthrough],
         [
           declare: fn _, _, _ -> {:ok, %{}} end,
           bind: fn _, _, _, _ -> :ok end
         ]}
      ]) do
        assert EventListener.should_listen(broker) == true
        assert EventListener.get_handlers(broker) == handlers

        state = EventListener.initial_state(broker, table)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker,
          table: table
        }

        assert state == expected_state

        result = EventListener.create_topology(chan, state)
        assert result == {:ok, state}

        retry_exchange = "#{app_name}.#{events_exchange}"
        dlq_exchange = "#{retry_exchange}.DLQ"

        assert called(AMQP.Exchange.declare(chan, events_exchange, :topic, durable: true))
        assert called(AMQP.Exchange.declare(chan, retry_exchange, :topic, durable: true))
        assert called(AMQP.Exchange.declare(chan, dlq_exchange, :topic, durable: true))

        assert called(
                 AMQP.Queue.bind(chan, queue_name, events_exchange, routing_key: "event.type1")
               )

        assert called(
                 AMQP.Queue.bind(chan, queue_name, events_exchange, routing_key: "event.type2")
               )
      end
    end
  end
end
