defmodule DiscardNotifierTest do
  use ExUnit.Case
  doctest DiscardNotifier
  import Mock

  @broker :app

  test_with_mock "should notify discarded command", DomainEventBus, emit: fn _, _ -> :ok end do
    assert_emit_ok(~s/{"name": "command1", "commandId": "42", "data": "Hello"}/)

    assert_called(
      DomainEventBus.emit(@broker, %DomainEvent{
        data: "Hello",
        eventId: "42",
        name: "command1.dlq"
      })
    )
  end

  test_with_mock "should notify discarded event", DomainEventBus, emit: fn _, _ -> :ok end do
    assert_emit_ok(~s/{"name": "event1", "eventId": "41", "data": "Hello"}/)

    assert_called(
      DomainEventBus.emit(@broker, %DomainEvent{data: "Hello", eventId: "41", name: "event1.dlq"})
    )
  end

  test_with_mock "should notify discarded query", DomainEventBus, emit: fn _, _ -> :ok end do
    assert_emit_ok(~s/{"resource": "query1", "queryData": "Hello"}/)

    assert_called(
      DomainEventBus.emit(@broker, %DomainEvent{
        data: "Hello",
        eventId: "query1query",
        name: "query1.dlq"
      })
    )
  end

  test_with_mock "should notify unknown message type", DomainEventBus, emit: fn _, _ -> :ok end do
    json = ~s/{"name1": "data", "otherProp": "Hello"}/
    assert_emit_ok(json)

    assert_called(
      DomainEventBus.emit(@broker, %DomainEvent{
        data: json,
        eventId: "corruptData",
        name: "corruptData.dlq"
      })
    )
  end

  test_with_mock "should notify unreadable message", DomainEventBus, emit: fn _, _ -> :ok end do
    data = "This is invalid json data"
    assert_emit_ok(data)

    assert_called(
      DomainEventBus.emit(@broker, %DomainEvent{
        data: data,
        eventId: "corruptData",
        name: "corruptData.dlq"
      })
    )
  end

  defp assert_emit_ok(json) do
    message = %MessageToHandle{payload: json}
    assert DiscardNotifier.notify(message, @broker) == :ok
  end
end
