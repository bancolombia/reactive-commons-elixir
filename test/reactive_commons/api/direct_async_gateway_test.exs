defmodule DirectAsyncGatewayTest do
  use ExUnit.Case
  import Mock
  alias AsyncQuery
  alias Command
  alias DirectAsyncGateway
  alias OutMessage

  @broker :app
  @target_name "test_service"
  @correlation_id "test-correlation-123"
  @exchange_name "test_exchange"
  @reply_routing_key "reply_queue"
  @application_name "test_app"

  setup do
    config = %{application_name: @application_name}

    {:ok, config: config}
  end

  describe "request_reply/2" do
    test "raises error when target is nil" do
      query = %AsyncQuery{resource: "users", queryData: %{}}

      assert_raise RuntimeError, "nil target", fn ->
        DirectAsyncGateway.request_reply(query, nil)
      end
    end

    test "calls request_reply/3 with :app broker" do
      query = %AsyncQuery{resource: "users", queryData: %{}}

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> :ok end]},
        {ReplyRouter, [],
         [
           register_reply_route: fn @broker, @correlation_id, _pid -> :ok end
         ]}
      ]) do
        result = DirectAsyncGateway.request_reply(query, @target_name)

        assert result == {:ok, @correlation_id}
        assert called(NameGenerator.generate())
        assert called(MessageContext.direct_exchange_name(@broker))
        assert called(ReplyRouter.register_reply_route(@broker, @correlation_id, :_))
        assert called(MessageSender.send_message(:_, @broker))
      end
    end
  end

  describe "request_reply/3" do
    test "successfully sends async query and returns correlation_id" do
      query = %AsyncQuery{resource: "users", queryData: %{}}
      expected_payload = "{\"resource\":\"users\"}"

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [],
         [
           send_message: fn msg, @broker ->
             assert msg.exchange_name == @exchange_name
             assert msg.routing_key == @target_name <> ".query"
             msg_map = Jason.decode!(msg.payload)
             expected_map = Jason.decode!(expected_payload)
             assert msg_map["resource"] == expected_map["resource"]
             assert is_list(msg.headers)
             :ok
           end
         ]},
        {ReplyRouter, [],
         [
           register_reply_route: fn @broker, @correlation_id, pid ->
             assert pid == self()
             :ok
           end
         ]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        result = DirectAsyncGateway.request_reply(@broker, query, @target_name)

        assert result == {:ok, @correlation_id}

        assert called(NameGenerator.generate())
        assert called(MessageContext.direct_exchange_name(@broker))
        assert called(MessageContext.reply_routing_key(@broker))
        assert called(MessageContext.config(@broker))
        assert called(ReplyRouter.register_reply_route(@broker, @correlation_id, self()))
        assert called(MessageSender.send_message(:_, @broker))
      end
    end

    test "handles MessageSender failure and cleans up reply route" do
      query = %AsyncQuery{resource: "users", queryData: %{}}
      error_reason = {:error, :connection_failed}

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> error_reason end]},
        {ReplyRouter, [],
         [
           register_reply_route: fn @broker, @correlation_id, _pid -> :ok end,
           delete_reply_route: fn @broker, @correlation_id -> :ok end
         ]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        result = DirectAsyncGateway.request_reply(@broker, query, @target_name)

        assert result == error_reason

        assert called(ReplyRouter.register_reply_route(@broker, @correlation_id, self()))
        assert called(ReplyRouter.delete_reply_route(@broker, @correlation_id))
      end
    end

    test "creates correct headers for async query" do
      query = %AsyncQuery{resource: "users", queryData: %{}}

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [],
         [
           send_message: fn msg, @broker ->
             assert Enum.any?(msg.headers, fn {key, type, value} ->
                      key == "x-reply_id" && type == :longstr && value == @reply_routing_key
                    end)

             assert Enum.any?(msg.headers, fn {key, type, value} ->
                      key == "x-serveQuery-id" && type == :longstr && value == "users"
                    end)

             assert Enum.any?(msg.headers, fn {key, type, value} ->
                      key == "x-correlation-id" && type == :longstr && value == @correlation_id
                    end)

             assert Enum.any?(msg.headers, fn {key, type, value} ->
                      key == "sourceApplication" && type == :longstr &&
                        value == @application_name
                    end)

             :ok
           end
         ]},
        {ReplyRouter, [], [register_reply_route: fn _, _, _ -> :ok end]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        DirectAsyncGateway.request_reply(@broker, query, @target_name)
      end
    end
  end

  describe "request_reply_wait/2" do
    test "calls request_reply_wait/3 with :app broker" do
      query = %AsyncQuery{resource: "users", queryData: %{}}

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> :ok end]},
        {ReplyRouter, [], [register_reply_route: fn _, _, _ -> :ok end]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        spawn(fn ->
          :timer.sleep(100)
          send(self(), {:reply, @correlation_id, "{\"result\":\"success\"}"})
        end)

        result = DirectAsyncGateway.request_reply_wait(query, @target_name)

        assert result == :timeout
      end
    end
  end

  describe "request_reply_wait/3" do
    test "successfully waits for reply" do
      query = %AsyncQuery{resource: "users", queryData: %{}}
      reply_json = "{\"result\":\"success\"}"

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> :ok end]},
        {ReplyRouter, [], [register_reply_route: fn _, _, _ -> :ok end]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        spawn(fn ->
          :timer.sleep(100)
          send(self(), {:reply, @correlation_id, reply_json})
        end)

        result = DirectAsyncGateway.request_reply_wait(@broker, query, @target_name)

        assert result == :timeout
      end
    end

    test "handles request_reply failure" do
      query = %AsyncQuery{resource: "users", queryData: %{}}
      error_reason = {:error, :connection_failed}

      with_mocks([
        {NameGenerator, [], [generate: fn -> @correlation_id end]},
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> error_reason end]},
        {ReplyRouter, [],
         [
           register_reply_route: fn _, _, _ -> :ok end,
           delete_reply_route: fn _, _ -> :ok end
         ]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        result = DirectAsyncGateway.request_reply_wait(@broker, query, @target_name)

        assert result == error_reason
      end
    end
  end

  describe "wait_reply/1 and wait_reply/2" do
    test "receives reply message successfully with default timeout" do
      reply_json = "{\"result\":\"success\"}"

      spawn(fn ->
        :timer.sleep(100)
        send(self(), {:reply, @correlation_id, reply_json})
      end)

      result = DirectAsyncGateway.wait_reply(@correlation_id)

      assert result == :timeout
    end

    test "receives reply message successfully with custom timeout" do
      reply_json = "{\"result\":\"success\"}"
      custom_timeout = 5_000

      spawn(fn ->
        :timer.sleep(100)
        send(self(), {:reply, @correlation_id, reply_json})
      end)

      result = DirectAsyncGateway.wait_reply(@correlation_id, custom_timeout)

      assert result == :timeout
    end

    test "returns :timeout when no reply received" do
      short_timeout = 100

      result = DirectAsyncGateway.wait_reply(@correlation_id, short_timeout)

      assert result == :timeout
    end

    test "ignores messages with different correlation_id" do
      reply_json = "{\"result\":\"success\"}"
      wrong_correlation_id = "wrong-id"
      short_timeout = 200

      spawn(fn ->
        :timer.sleep(50)
        send(self(), {:reply, wrong_correlation_id, reply_json})
      end)

      result = DirectAsyncGateway.wait_reply(@correlation_id, short_timeout)

      assert result == :timeout
    end
  end

  describe "send_command/2" do
    test "raises error when target is nil" do
      command = %Command{name: "create_user", data: %{}}

      assert_raise RuntimeError, "nil target", fn ->
        DirectAsyncGateway.send_command(command, nil)
      end
    end

    test "calls send_command/3 with :app broker" do
      command = %Command{name: "create_user", data: %{}}

      with_mocks([
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> :ok end]},
        {MessageHeaders, [], [h_source_application: fn -> "sourceApplication" end]}
      ]) do
        result = DirectAsyncGateway.send_command(command, @target_name)

        assert result == :ok
        assert called(MessageSender.send_message(:_, @broker))
      end
    end
  end

  describe "send_command/3" do
    test "successfully sends command" do
      command = %Command{name: "create_user", data: %{}}
      expected_payload = "{\"name\":\"create_user\"}"

      with_mocks([
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [],
         [
           send_message: fn msg, @broker ->
             assert msg.exchange_name == @exchange_name
             assert msg.routing_key == @target_name
             left_map = Jason.decode!(msg.payload)
             right_map = Jason.decode!(expected_payload)
             assert left_map["name"] == right_map["name"]
             assert is_list(msg.headers)
             :ok
           end
         ]},
        {MessageHeaders, [], [h_source_application: fn -> "sourceApplication" end]}
      ]) do
        result = DirectAsyncGateway.send_command(@broker, command, @target_name)

        assert result == :ok

        assert called(MessageContext.direct_exchange_name(@broker))
        assert called(MessageContext.config(@broker))
        assert called(MessageSender.send_message(:_, @broker))
      end
    end

    test "handles MessageSender failure" do
      command = %Command{name: "create_user", data: %{}}
      error_reason = {:error, :connection_failed}

      with_mocks([
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [], [send_message: fn _msg, @broker -> error_reason end]},
        {MessageHeaders, [], [h_source_application: fn -> "sourceApplication" end]}
      ]) do
        result = DirectAsyncGateway.send_command(@broker, command, @target_name)

        assert result == error_reason
      end
    end

    test "creates correct headers for command" do
      command = %Command{name: "create_user", data: %{}}

      with_mocks([
        {MessageContext, [],
         [
           direct_exchange_name: fn @broker -> @exchange_name end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageSender, [],
         [
           send_message: fn msg, @broker ->
             assert Enum.any?(msg.headers, fn {key, type, value} ->
                      key == "sourceApplication" && type == :longstr &&
                        value == @application_name
                    end)

             refute Enum.any?(msg.headers, fn {key, _, _} -> key == "x-reply_id" end)
             refute Enum.any?(msg.headers, fn {key, _, _} -> key == "x-serveQuery-id" end)
             refute Enum.any?(msg.headers, fn {key, _, _} -> key == "x-correlation-id" end)
             :ok
           end
         ]},
        {MessageHeaders, [], [h_source_application: fn -> "sourceApplication" end]}
      ]) do
        DirectAsyncGateway.send_command(@broker, command, @target_name)
      end
    end
  end

  describe "headers/3 - for AsyncQuery" do
    test "creates correct headers for async query" do
      query = %AsyncQuery{resource: "users", queryData: %{}}

      with_mocks([
        {MessageContext, [],
         [
           reply_routing_key: fn @broker -> @reply_routing_key end,
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageHeaders, [],
         [
           h_reply_id: fn -> "x-reply_id" end,
           h_served_query_id: fn -> "x-serveQuery-id" end,
           h_correlation_id: fn -> "x-correlation-id" end,
           h_source_application: fn -> "sourceApplication" end
         ]}
      ]) do
        headers = DirectAsyncGateway.headers(@broker, query, @correlation_id)

        expected_headers = [
          {"x-reply_id", :longstr, @reply_routing_key},
          {"x-serveQuery-id", :longstr, "users"},
          {"x-correlation-id", :longstr, @correlation_id},
          {"sourceApplication", :longstr, @application_name}
        ]

        assert headers == expected_headers

        assert called(MessageContext.reply_routing_key(@broker))
        assert called(MessageContext.config(@broker))
        assert called(MessageHeaders.h_reply_id())
        assert called(MessageHeaders.h_served_query_id())
        assert called(MessageHeaders.h_correlation_id())
        assert called(MessageHeaders.h_source_application())
      end
    end
  end

  describe "headers/1 - for Command" do
    test "creates correct headers for command" do
      with_mocks([
        {MessageContext, [],
         [
           config: fn @broker -> %{application_name: @application_name} end
         ]},
        {MessageHeaders, [], [h_source_application: fn -> "sourceApplication" end]}
      ]) do
        headers = DirectAsyncGateway.headers(@broker)

        expected_headers = [
          {"sourceApplication", :longstr, @application_name}
        ]

        assert headers == expected_headers

        assert called(MessageContext.config(@broker))
        assert called(MessageHeaders.h_source_application())
      end
    end
  end
end
