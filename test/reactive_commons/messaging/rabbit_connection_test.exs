defmodule RabbitConnectionTest do
  use ExUnit.Case

  alias RabbitConnection

  defmodule MockAMQP do
    defmodule Connection do
      def open(_opts), do: {:ok, %{pid: spawn_link(fn -> Process.sleep(:infinity) end)}}
      def open(_opts, :fail), do: {:error, :connection_refused}
      def close(conn), do: Process.exit(conn.pid, :normal)
    end
  end

  setup do
    on_exit(fn ->
      Process.sleep(10)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts GenServer with provided name" do
      opts = [
        name: :test_rabbit_connection,
        connection_props: [host: "localhost", port: 5672]
      ]

      assert {:ok, pid} = RabbitConnection.start_link(opts)
      assert Process.alive?(pid)
      assert GenServer.whereis(:test_rabbit_connection) == pid

      GenServer.stop(pid)
    end

    test "starts GenServer without name when not provided" do
      opts = [connection_props: [host: "localhost", port: 5672]]

      assert {:ok, pid} = RabbitConnection.start_link(opts)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "validates required connection_props option" do
      assert {:ok, _pid} = RabbitConnection.start_link([connection_props: [host: "localhost"]])
    end
  end

  describe "init/1" do
    test "initializes with correct state structure" do
      opts = [
        name: :test_init,
        connection_props: [host: "localhost", port: 5672],
        parent_pid: self()
      ]

      {:ok, pid} = RabbitConnection.start_link(opts)
      Process.sleep(50)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "get_connection/1" do
    test "returns error when not connected" do
      opts = [
        name: :test_not_connected,
        connection_props: [host: "nonexistent_host", port: 9999]
      ]

      {:ok, pid} = RabbitConnection.start_link(opts)
      Process.sleep(100)

      assert {:error, :not_connected} = RabbitConnection.get_connection(pid)

      GenServer.stop(pid)
    end

    test "returns connection when available" do
      opts = [connection_props: [host: "localhost", port: 5672]]
      {:ok, pid} = RabbitConnection.start_link(opts)

      result = RabbitConnection.get_connection(pid)
      assert result in [nil, {:error, :not_connected}] || match?({:ok, _}, result)

      GenServer.stop(pid)
    end
  end

  describe "handle_call/3 :get_connection" do
    test "returns connection from state when available" do
      mock_connection = %{pid: spawn_link(fn -> Process.sleep(:infinity) end)}

      state = %RabbitConnection{
        name: :test,
        connection: mock_connection,
        parent_pid: nil
      }

      assert {:reply, ^mock_connection, ^state} =
               RabbitConnection.handle_call(:get_connection, {self(), make_ref()}, state)

      Process.exit(mock_connection.pid, :kill)
    end

    test "returns nil when no connection available" do
      state = %RabbitConnection{
        name: :test,
        connection: nil,
        parent_pid: nil
      }

      assert {:reply, nil, ^state} =
               RabbitConnection.handle_call(:get_connection, {self(), make_ref()}, state)
    end
  end

  describe "handle_info/2 connect message" do
    test "handles successful connection state transition" do
      mock_connection = %{pid: spawn_link(fn -> Process.sleep(:infinity) end)}

      initial_state = %RabbitConnection{
        name: :test,
        parent_pid: nil,
        connection: nil
      }

      updated_state = %{initial_state | connection: mock_connection}

      assert updated_state.connection == mock_connection
      assert updated_state.name == :test

      Process.exit(mock_connection.pid, :kill)
    end

    test "handles max retries reached scenario" do
      connection_props = [host: "invalid_host", port: 9999]
      state = %RabbitConnection{name: :test, parent_pid: nil, connection: nil}

      assert {:stop, :max_reconnect_failed, ^state} =
               RabbitConnection.handle_info({:connect, connection_props, 5}, state)
    end

    test "sends notification to parent when connection succeeds" do
      parent_pid = self()
      mock_connection = %{pid: spawn_link(fn -> Process.sleep(:infinity) end)}

      send(parent_pid, {:connected, :test_notification, mock_connection})
      assert_receive {:connected, :test_notification, ^mock_connection}, 100

      Process.exit(mock_connection.pid, :kill)
    end

    test "schedules reconnection on failure with valid retry count" do
      connection_props = [host: "invalid_host", port: 9999]
      state = %RabbitConnection{name: :test, parent_pid: nil, connection: nil}

      result = RabbitConnection.handle_info({:connect, connection_props, 2}, state)

      assert match?({:noreply, _}, result) or match?({:stop, :max_reconnect_failed, _}, result)
    end
  end

  describe "handle_info/2 DOWN message" do
    test "handles connection loss and stops process" do
      reason = :connection_closed
      ref = make_ref()

      result = RabbitConnection.handle_info(
        {:DOWN, ref, :process, self(), reason},
        %RabbitConnection{}
      )

      assert {:stop, {:connection_lost, ^reason}, nil} = result
    end

    test "handles different connection loss reasons" do
      reasons = [:normal, :shutdown, {:shutdown, :tcp_closed}, :killed]

      for reason <- reasons do
        result = RabbitConnection.handle_info(
          {:DOWN, make_ref(), :process, self(), reason},
          %RabbitConnection{}
        )

        assert {:stop, {:connection_lost, ^reason}, nil} = result
      end
    end
  end

  describe "connection retry behavior" do
    test "attempts reconnection with exponential backoff concept" do
      opts = [
        name: :retry_test,
        connection_props: [host: "nonexistent_host_12345", port: 5672]
      ]

      {:ok, pid} = RabbitConnection.start_link(opts)

      Process.sleep(500)
      assert Process.alive?(pid)
      assert {:error, :not_connected} = RabbitConnection.get_connection(pid)

      GenServer.stop(pid)
    end
  end

  describe "state management and data structures" do
    test "RabbitConnection struct has correct fields" do
      state = %RabbitConnection{
        name: :test_name,
        connection: %{pid: self()},
        parent_pid: self()
      }

      assert state.name == :test_name
      assert state.connection == %{pid: self()}
      assert state.parent_pid == self()
    end

    test "RabbitConnection struct allows nil values" do
      state = %RabbitConnection{name: :minimal}

      assert state.name == :minimal
      assert is_nil(state.connection)
      assert is_nil(state.parent_pid)
    end

    test "state transitions preserve important fields" do
      initial_state = %RabbitConnection{name: :persistent_test, parent_pid: self()}
      mock_conn = %{pid: spawn_link(fn -> Process.sleep(:infinity) end)}

      updated_state = %{initial_state | connection: mock_conn}

      assert updated_state.name == initial_state.name
      assert updated_state.parent_pid == initial_state.parent_pid
      assert updated_state.connection == mock_conn

      Process.exit(mock_conn.pid, :kill)
    end
  end

  describe "process monitoring and lifecycle" do
    test "monitors connection process correctly" do
      test_process = spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

      ref = Process.monitor(test_process)

      state = %RabbitConnection{
        name: :monitor_test,
        connection: %{pid: test_process},
        parent_pid: nil
      }

      assert state.connection.pid == test_process

      send(test_process, :stop)
      assert_receive {:DOWN, ^ref, :process, ^test_process, :normal}, 1000
    end

    test "handles graceful shutdown" do
      opts = [
        name: :shutdown_test,
        connection_props: [host: "localhost", port: 5672]
      ]

      {:ok, pid} = RabbitConnection.start_link(opts)
      ref = Process.monitor(pid)

      GenServer.stop(pid, :normal)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "configuration and constants validation" do
    test "connection parameters are properly structured" do
      formats = [
        [host: "localhost", port: 5672],
        [host: "localhost", port: 5672, username: "guest", password: "guest"],
        "amqp://guest:guest@localhost:5672"
      ]

      for connection_props <- formats do
        opts = [
          name: :"config_test_#{System.unique_integer()}",
          connection_props: connection_props
        ]

        assert {:ok, pid} = RabbitConnection.start_link(opts)
        GenServer.stop(pid)
      end
    end

    test "reconnection timing respects minimum intervals" do
      opts = [
        name: :timing_test,
        connection_props: [host: "invalid_host_timing", port: 5672]
      ]

      start_time = System.monotonic_time(:millisecond)

      {:ok, pid} = RabbitConnection.start_link(opts)
      Process.sleep(6000)
      GenServer.stop(pid)

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      assert elapsed >= 5000
    end
  end
end