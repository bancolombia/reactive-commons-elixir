defmodule QueueListenerTest do
  use ExUnit.Case
  import Mock

  alias QueueListener

  describe "should_listen/1" do
    test "returns always true" do
      broker = :test_broker
      assert QueueListener.should_listen(broker) == true
    end
  end

  describe "get_handlers/1" do
    test "returns queue listeners from message context" do
      broker = :test_broker
      queue_name = "custom.queue"
      handlers = %{broker => %{queue_name => :some_handler}}
      expected_handlers = %{broker => %{"default" => :some_handler}}

      with_mock MessageContext, [:passthrough],
        handlers: fn ^broker -> %{queue_listeners: handlers} end do
        result = QueueListener.get_handlers(%{broker: broker, queue_name: queue_name})

        assert result == expected_handlers
        assert_called(MessageContext.handlers(broker))
      end
    end
  end

  describe "initial_state/1" do
    test "returns correct initial state with all required fields" do
      broker = :test_broker
      table = :event_test_broker_table
      queue_name = "some-custom-queue"
      prefetch_count = 15

      with_mock MessageContext, [:passthrough], prefetch_count: fn ^broker -> prefetch_count end do
        result = QueueListener.initial_state(%{broker: broker, queue_name: queue_name}, table)

        expected_state = %{
          prefetch_count: prefetch_count,
          queue_name: queue_name,
          broker: broker,
          table: table
        }

        assert result == expected_state
        assert_called(MessageContext.prefetch_count(broker))
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

    test "generates correct table name format", %{table: _table, broker: broker} do
      with_mock MessageContext, [:passthrough],
        application_name: fn ^broker -> "test_app" end,
        event_queue_name: fn ^broker -> "test.queue" end,
        events_exchange_name: fn ^broker -> "test.exchange" end,
        with_dlq_retry: fn ^broker -> false end,
        retry_delay: fn ^broker -> 2 end do
      end
    end
  end
end
