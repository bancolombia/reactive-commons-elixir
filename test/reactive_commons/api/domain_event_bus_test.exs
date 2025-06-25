defmodule DomainEventBusTest do
  use ExUnit.Case
  import Mock

  alias DomainEventBus

  describe "emit/2" do
    test "sends message successfully" do
      event = %DomainEvent{name: "user.created", data: %{id: 1}}

      with_mocks([
        {MessageContext, [],
         [
           events_exchange_name: fn :app -> "test.exchange" end,
           config: fn :app -> %{application_name: "my_app"} end
         ]},
        {OutMessage, [],
         [
           new: fn opts ->
             %{
               exchange: opts[:exchange_name],
               key: opts[:routing_key],
               body: opts[:payload],
               headers: opts[:headers]
             }
           end
         ]},
        {MessageSender, [],
         [
           send_message: fn _msg, :app -> :ok end
         ]},
        {Poison, [],
         [
           encode!: fn ^event -> "{\"name\":\"user.created\",\"data\":{\"id\":1}}" end
         ]},
        {MessageHeaders, [],
         [
           h_source_application: fn -> "x-source-app" end
         ]}
      ]) do
        assert DomainEventBus.emit(:app, event) == :ok

        assert_called(MessageContext.events_exchange_name(:app))
        assert_called(MessageContext.config(:app))
        assert_called(Poison.encode!(event))
        assert_called(MessageSender.send_message(:_, :app))
      end
    end

    test "returns {:emit_fail, reason} if sending fails" do
      event = %DomainEvent{name: "order.failed"}

      with_mocks([
        {MessageContext, [],
         [
           events_exchange_name: fn _ -> "fail.exchange" end,
           config: fn _ -> %{application_name: "fail_app"} end
         ]},
        {OutMessage, [],
         [
           new: fn _opts -> :message_struct end
         ]},
        {Poison, [],
         [
           encode!: fn _event -> "{}" end
         ]},
        {MessageSender, [],
         [
           send_message: fn _, _ -> {:error, :network_down} end
         ]},
        {MessageHeaders, [],
         [
           h_source_application: fn -> "x-source-app" end
         ]}
      ]) do
        assert DomainEventBus.emit(:app, event) == {:emit_fail, {:error, :network_down}}
      end
    end
  end
end
