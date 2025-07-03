defmodule ConnectionsHolderTest do
  use ExUnit.Case
  import Mock
  alias ConnectionsHolder

  @broker "test_broker"
  @connection_props %{host: "localhost", port: 5672}
  @connection_assignation %{
    TestComponent: :test_connection,
    AnotherComponent: :another_connection
  }

  setup do
    case Process.whereis(SafeAtom.to_atom("connections_holder_#{@broker}")) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer with correct name" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          assert {:ok, pid} = ConnectionsHolder.start_link(@broker)
          assert is_pid(pid)
          assert Process.alive?(pid)

          expected_name = SafeAtom.to_atom("connections_holder_#{@broker}")
          assert Process.whereis(expected_name) == pid

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "init/1" do
    test "initializes state correctly" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)

          :timer.sleep(100)

          state = :sys.get_state(pid)

          assert state.broker == @broker
          assert state.connection_props == @connection_props
          assert state.connection_assignation == @connection_assignation
          assert is_map(state.connections)

          GenServer.stop(pid)
        end
      end
    end

    test "sends :init_connections message to self" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)

          :timer.sleep(100)

          assert called(RabbitConnection.start_link(:_))

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "get_connection_async/2" do
    setup do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)
          :timer.sleep(100)

          %{pid: pid}
        end
      end
    end

    test "returns :ok for valid component", %{pid: pid} do
      component_name = :test_component_instance

      result = ConnectionsHolder.get_connection_async(component_name, @broker)
      assert result == :ok

      GenServer.stop(pid)
    end

    test "returns :no_assignation for invalid component", %{pid: pid} do
      component_name = :invalid_component_instance

      result = ConnectionsHolder.get_connection_async(component_name, @broker)
      assert result == :no_assignation

      GenServer.stop(pid)
    end

    test "extracts module name correctly from component name", %{pid: pid} do
      component_name = :test_component_instance

      result = ConnectionsHolder.get_connection_async(component_name, @broker)
      assert result == :ok

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 - :send_connection" do
    setup do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)
          :timer.sleep(100)

          %{pid: pid}
        end
      end
    end

    test "retries when connection not available", %{pid: pid} do
      component_name = :test_component_instance
      ConnectionsHolder.get_connection_async(component_name, @broker)
      refute_receive {:connected, _}, 500

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 - :connected" do
    setup do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)
          :timer.sleep(100)

          %{pid: pid}
        end
      end
    end

    test "updates connection state when connection established", %{pid: pid} do
      conn_name = :test_connection_test_broker
      conn_ref = make_ref()

      send(pid, {:connected, conn_name, conn_ref})

      :timer.sleep(100)

      state = :sys.get_state(pid)
      assert Map.has_key?(state.connections, conn_name)
      assert Map.get(state.connections, conn_name)[:conn_ref] == conn_ref

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 - :init_connections" do
    test "starts connections for all configured connections" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough],
          start_link: fn opts ->
            assert opts[:connection_props] == @connection_props
            assert is_atom(opts[:name])
            assert is_pid(opts[:parent_pid])
            {:ok, self()}
          end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)

          :timer.sleep(100)

          assert called(RabbitConnection.start_link(:_))

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "private functions behavior" do
    test "build_name/1 creates correct atom" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)

          expected_name = SafeAtom.to_atom("connections_holder_#{@broker}")
          assert Process.whereis(expected_name) == pid

          GenServer.stop(pid)
        end
      end
    end

    test "extract_module_from_name/1 works correctly" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: %{TestComponent: :test_connection}
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          {:ok, pid} = ConnectionsHolder.start_link(@broker)
          :timer.sleep(100)

          result = ConnectionsHolder.get_connection_async(:test_component_instance, @broker)
          assert result == :ok

          result = ConnectionsHolder.get_connection_async(:invalid_name, @broker)
          assert result == :no_assignation

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "error handling" do
    test "handles missing configuration gracefully" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: nil,
            connection_assignation: %{}
          }
        end do
        with_mock RabbitConnection, [:passthrough], start_link: fn _opts -> {:ok, self()} end do
          assert {:ok, pid} = ConnectionsHolder.start_link(@broker)

          state = :sys.get_state(pid)
          assert state.connection_props == nil
          assert state.connection_assignation == %{}

          GenServer.stop(pid)
        end
      end
    end

    test "handles RabbitConnection start failure" do
      with_mock MessageContext, [:passthrough],
        config: fn @broker ->
          %{
            connection_props: @connection_props,
            connection_assignation: @connection_assignation
          }
        end do
        with_mock RabbitConnection, [:passthrough],
          start_link: fn _opts -> {:error, :connection_failed} end do
          assert {:ok, pid} = ConnectionsHolder.start_link(@broker)

          :timer.sleep(100)

          assert called(RabbitConnection.start_link(:_))

          GenServer.stop(pid)
        end
      end
    end
  end
end
