defmodule MessageContextTest do
  use ExUnit.Case

  @broker :test_broker
  @app_name "test_app"

  setup do
    config = %AsyncConfig{
      application_name: @app_name,
      broker: @broker
    }

    {:ok, pid} = MessageContext.start_link(config)
    %{pid: pid, config: config}
  end

  test "starts and stores default config in ETS" do
    stored = MessageContext.config(@broker)
    assert stored.application_name == @app_name
    assert stored.broker == @broker
    assert stored.prefetch_count == 250
    assert stored.reply_exchange == "globalReply"
  end

  test "retrieves queue and exchange information" do
    assert MessageContext.reply_exchange_name(@broker) == "globalReply"
    assert MessageContext.direct_exchange_name(@broker) == "directMessages"
    assert MessageContext.events_exchange_name(@broker) == "domainEvents"
    assert MessageContext.retry_delay(@broker) == 500
    assert MessageContext.max_retries(@broker) == 10
    assert MessageContext.prefetch_count(@broker) == 250
    assert MessageContext.application_name(@broker) == @app_name
    assert is_map(MessageContext.topology(@broker))
  end

  test "generates and saves reply queue name" do
    name = MessageContext.gen_reply_queue_name(@broker)
    assert String.contains?(name, "#{@app_name}-reply")
    assert MessageContext.reply_queue_name(@broker) == name
  end

  test "generates and saves notification event queue name" do
    name = MessageContext.gen_notification_event_queue_name(@broker)
    assert String.contains?(name, "#{@app_name}-notification")
    assert MessageContext.notification_event_queue_name(@broker) == name
  end

  test "saves and loads handlers config" do
    refute MessageContext.handlers_configured?(@broker)
    handlers = %HandlersConfig{}
    assert :ok == MessageContext.save_handlers_config(handlers, @broker)
    assert MessageContext.handlers_configured?(@broker)
    assert MessageContext.handlers(@broker) == handlers
  end

  test "table/1 returns ETS contents" do
    list = MessageContext.table(@broker)
    assert Enum.any?(list, fn {k, _} -> k == :conf end)
  end
end
