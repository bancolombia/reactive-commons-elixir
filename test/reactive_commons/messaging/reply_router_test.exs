defmodule ReplyRouterTest do
  use ExUnit.Case

  alias ReplyRouter

  describe "start_link/1" do
    test "starts GenServer with correct name" do
      broker = "test_broker"

      assert {:ok, pid} = ReplyRouter.start_link(broker)
      assert Process.alive?(pid)
      assert GenServer.whereis(:"reply_router_#{broker}") == pid

      GenServer.stop(pid)
    end

    test "creates ETS table on initialization" do
      broker = "test_broker_ets"

      {:ok, pid} = ReplyRouter.start_link(broker)

      table_name = :"reply_router_table_#{broker}"
      assert :ets.info(table_name) != :undefined

      GenServer.stop(pid)
    end
  end

  describe "register_reply_route/3" do
    setup do
      broker = "test_broker_register"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "registers a reply route successfully", %{broker: broker} do
      correlation_id = "test_correlation_id"
      test_pid = self()

      assert :ok = ReplyRouter.register_reply_route(broker, correlation_id, test_pid)

      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      assert [{^key, ^test_pid}] = :ets.lookup(table_name, key)
    end

    test "overwrites existing route for same correlation_id", %{broker: broker} do
      correlation_id = "test_correlation_id"
      old_pid = spawn(fn -> :ok end)
      new_pid = self()

      ReplyRouter.register_reply_route(broker, correlation_id, old_pid)

      assert :ok = ReplyRouter.register_reply_route(broker, correlation_id, new_pid)

      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      assert [{^key, ^new_pid}] = :ets.lookup(table_name, key)
    end
  end

  describe "delete_reply_route/2" do
    setup do
      broker = "test_broker_delete"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "deletes existing reply route", %{broker: broker} do
      correlation_id = "test_correlation_id"
      test_pid = self()

      ReplyRouter.register_reply_route(broker, correlation_id, test_pid)

      :ok = ReplyRouter.delete_reply_route(broker, correlation_id)

      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      :timer.sleep(10)

      assert [] = :ets.lookup(table_name, key)
    end

    test "delete non-existing route doesn't fail", %{broker: broker} do
      correlation_id = "non_existing_correlation_id"

      assert :ok = ReplyRouter.delete_reply_route(broker, correlation_id)
    end
  end

  describe "route_reply/3" do
    setup do
      broker = "test_broker_route"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "routes reply to registered process and deletes route", %{broker: broker} do
      correlation_id = "test_correlation_id"
      reply_message = "test_reply_message"
      test_pid = self()

      ReplyRouter.register_reply_route(broker, correlation_id, test_pid)

      assert :ok = ReplyRouter.route_reply(broker, correlation_id, reply_message)

      assert_receive {:reply, ^correlation_id, ^reply_message}, 100

      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      :timer.sleep(10)

      assert [] = :ets.lookup(table_name, key)
    end

    test "returns :no_route when correlation_id not found", %{broker: broker} do
      correlation_id = "non_existing_correlation_id"
      reply_message = "test_reply_message"

      assert :no_route = ReplyRouter.route_reply(broker, correlation_id, reply_message)

      refute_receive {:reply, _, _}, 50
    end

    test "handles different data types for correlation_id and reply_message", %{broker: broker} do
      correlation_id = 12345
      reply_message = %{status: :ok, data: "test"}
      test_pid = self()

      ReplyRouter.register_reply_route(broker, correlation_id, test_pid)

      assert :ok = ReplyRouter.route_reply(broker, correlation_id, reply_message)

      assert_receive {:reply, ^correlation_id, ^reply_message}, 100
    end
  end

  describe "handle_call/3" do
    setup do
      broker = "test_broker_handle_call"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "handle_call for register inserts into ETS table", %{broker: broker, pid: server_pid} do
      correlation_id = "test_correlation_id"
      test_pid = self()

      assert :ok =
               GenServer.call(server_pid, {:register, broker, correlation_id, test_pid})

      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      assert [{^key, ^test_pid}] = :ets.lookup(table_name, key)
    end
  end

  describe "handle_cast/2" do
    setup do
      broker = "test_broker_handle_cast"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "handle_cast for delete removes from ETS table", %{broker: broker, pid: server_pid} do
      correlation_id = "test_correlation_id"
      table_name = :"reply_router_table_#{broker}"
      key = {to_string(broker), correlation_id}

      assert :ok =
               GenServer.cast(server_pid, {:delete, broker, correlation_id})

      :timer.sleep(10)

      assert [] = :ets.lookup(table_name, key)
    end
  end

  describe "private functions" do
    test "build_name/1 creates correct atom" do
      broker = "test_broker"

      {:ok, pid} = ReplyRouter.start_link(broker)

      assert GenServer.whereis(:"reply_router_#{broker}") == pid

      GenServer.stop(pid)
    end

    test "table_name/1 creates correct table name" do
      broker = "test_broker_table"
      {:ok, pid} = ReplyRouter.start_link(broker)

      table_name = :"reply_router_table_#{broker}"
      assert :ets.info(table_name) != :undefined

      GenServer.stop(pid)
    end
  end

  describe "integration scenarios" do
    setup do
      broker = "integration_broker"
      {:ok, pid} = ReplyRouter.start_link(broker)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        table_name = :"reply_router_table_#{broker}"

        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{broker: broker, pid: pid}
    end

    test "complete workflow: register -> route -> cleanup", %{broker: broker} do
      correlation_id = "integration_test_id"
      reply_message = "integration_reply"
      test_pid = self()

      assert :ok = ReplyRouter.register_reply_route(broker, correlation_id, test_pid)

      assert :ok = ReplyRouter.route_reply(broker, correlation_id, reply_message)

      assert_receive {:reply, ^correlation_id, ^reply_message}, 100

      :timer.sleep(10)
      assert :no_route = ReplyRouter.route_reply(broker, correlation_id, "another_message")
    end

    test "multiple concurrent routes", %{broker: broker} do
      test_pid = self()

      Enum.each(1..5, fn i ->
        correlation_id = "test_id_#{i}"
        ReplyRouter.register_reply_route(broker, correlation_id, test_pid)
      end)

      Enum.each(1..5, fn i ->
        correlation_id = "test_id_#{i}"
        reply_message = "reply_#{i}"
        assert :ok = ReplyRouter.route_reply(broker, correlation_id, reply_message)
      end)

      Enum.each(1..5, fn i ->
        correlation_id = "test_id_#{i}"
        reply_message = "reply_#{i}"
        assert_receive {:reply, ^correlation_id, ^reply_message}, 100
      end)
    end
  end
end
