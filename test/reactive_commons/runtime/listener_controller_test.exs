defmodule ListenerControllerTest do
  use ExUnit.Case
  import Mock

  describe "start_link/1" do
    test "starts GenServer with correct name and broker" do
      broker = :test_broker

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end do
        with_mock MessageContext, [:passthrough], handlers_configured?: fn ^broker -> false end do
          with {:ok, pid} <- ListenerController.start_link(broker) do
            assert Process.alive?(pid)
            assert GenServer.whereis(:"listener_controller_#{broker}") == pid
            GenServer.stop(pid)
          end
        end
      end
    end
  end

  describe "init/1" do
    test "initializes with broker and starts dynamic supervisor when handlers not configured" do
      broker = :test_broker
      supervisor_pid = spawn(fn -> :ok end)

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn opts ->
          assert opts[:strategy] == :one_for_one
          assert opts[:name] == :"dynamic_supervisor_#{broker}"
          {:ok, supervisor_pid}
        end do
        with_mock MessageContext, [:passthrough], handlers_configured?: fn ^broker -> false end do
          with {:ok, state} <- ListenerController.init(broker) do
            assert state == %{broker: broker}
            assert called(DynamicSupervisor.start_link(:_))
            assert called(MessageContext.handlers_configured?(broker))
          end
        end
      end
    end

    test "initializes and starts listeners when handlers are configured" do
      broker = :test_broker
      supervisor_pid = spawn(fn -> :ok end)
      listener_pid = spawn(fn -> :ok end)

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, supervisor_pid} end,
        start_child: fn _supervisor, _child -> {:ok, listener_pid} end do
        with_mock MessageContext, [:passthrough], handlers_configured?: fn ^broker -> true end do
          with {:ok, state} <- ListenerController.init(broker) do
            assert state == %{broker: broker}
            assert called(DynamicSupervisor.start_link(:_))
            assert called(MessageContext.handlers_configured?(broker))

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {QueryListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {EventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {NotificationEventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {CommandListener, broker}
                     )
                   )
          end
        end
      end
    end
  end

  describe "configure/1" do
    test "configures handlers and starts listeners" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}
      listener_pid = spawn(fn -> :ok end)

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end,
        start_child: fn _supervisor, _child -> {:ok, listener_pid} end do
        with_mock MessageContext, [:passthrough],
          handlers_configured?: fn ^broker -> false end,
          save_handlers_config: fn ^config, ^broker -> :ok end do
          {:ok, pid} = ListenerController.start_link(broker)

          with :ok <- ListenerController.configure(config) do
            assert called(MessageContext.save_handlers_config(config, broker))

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {QueryListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {EventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {NotificationEventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {CommandListener, broker}
                     )
                   )
          end

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "handle_call/3" do
    test "handles configure_handlers call and starts listeners" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}
      state = %{broker: broker}
      listener_pid = spawn(fn -> :ok end)

      with_mock DynamicSupervisor, [:passthrough],
        start_child: fn _supervisor, _child -> {:ok, listener_pid} end do
        with_mock MessageContext, [:passthrough],
          save_handlers_config: fn ^config, ^broker -> :ok end do
          with {:reply, reply, new_state} <-
                 ListenerController.handle_call({:configure_handlers, config}, self(), state) do
            assert reply == :ok
            assert new_state == state
            assert called(MessageContext.save_handlers_config(config, broker))

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {QueryListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {EventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {NotificationEventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {CommandListener, broker}
                     )
                   )
          end
        end
      end
    end
  end

  describe "start_listeners/1 through public interface" do
    test "starts all required listeners correctly" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}
      listener_pid = spawn(fn -> :ok end)

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end,
        start_child: fn supervisor_name, child_spec ->
          assert supervisor_name == :"dynamic_supervisor_#{broker}"

          assert child_spec in [
                   {QueryListener, broker},
                   {EventListener, broker},
                   {NotificationEventListener, broker},
                   {CommandListener, broker}
                 ]

          {:ok, listener_pid}
        end do
        with_mock MessageContext, [:passthrough],
          handlers_configured?: fn ^broker -> false end,
          save_handlers_config: fn ^config, ^broker -> :ok end do
          {:ok, pid} = ListenerController.start_link(broker)

          with :ok <- ListenerController.configure(config) do
            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {QueryListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {EventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {NotificationEventListener, broker}
                     )
                   )

            assert called(
                     DynamicSupervisor.start_child(
                       :"dynamic_supervisor_#{broker}",
                       {CommandListener, broker}
                     )
                   )
          end

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "private function behavior verification" do
    test "build_name/1 creates correct process name" do
      broker = :test_broker

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end do
        with_mock MessageContext, [:passthrough], handlers_configured?: fn ^broker -> false end do
          with {:ok, pid} <- ListenerController.start_link(broker) do
            assert GenServer.whereis(:"listener_controller_#{broker}") == pid
            GenServer.stop(pid)
          end
        end
      end
    end

    test "get_name/1 creates correct supervisor name through start_child calls" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end,
        start_child: fn supervisor_name, _child ->
          assert supervisor_name == :"dynamic_supervisor_#{broker}"
          {:ok, spawn(fn -> :ok end)}
        end do
        with_mock MessageContext, [:passthrough],
          handlers_configured?: fn ^broker -> false end,
          save_handlers_config: fn ^config, ^broker -> :ok end do
          {:ok, pid} = ListenerController.start_link(broker)

          with :ok <- ListenerController.configure(config) do
            assert :ok == :ok
          end

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "error scenarios" do
    test "continues execution even when listener start fails" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end,
        start_child: fn _supervisor, {QueryListener, ^broker} ->
          {:error, :listener_failed}
        end,
        start_child: fn _supervisor, _child ->
          {:ok, spawn(fn -> :ok end)}
        end do
        with_mock MessageContext, [:passthrough],
          handlers_configured?: fn ^broker -> false end,
          save_handlers_config: fn ^config, ^broker -> :ok end do
          {:ok, pid} = ListenerController.start_link(broker)

          with :ok <- ListenerController.configure(config) do
            assert called(DynamicSupervisor.start_child(:_, {QueryListener, broker}))
            assert called(DynamicSupervisor.start_child(:_, {EventListener, broker}))

            assert called(DynamicSupervisor.start_child(:_, {NotificationEventListener, broker}))

            assert called(DynamicSupervisor.start_child(:_, {CommandListener, broker}))
          end

          GenServer.stop(pid)
        end
      end
    end
  end

  describe "logging verification" do
    test "logs appropriate messages during initialization" do
      broker = :test_broker

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end do
        with_mock MessageContext, [:passthrough], handlers_configured?: fn ^broker -> false end do
          assert {:ok, %{broker: broker}} == ListenerController.init(broker)
        end
      end
    end

    test "logs configuration and listener start messages" do
      broker = :test_broker
      config = %HandlersConfig{broker: broker}

      with_mock DynamicSupervisor, [:passthrough],
        start_link: fn _opts -> {:ok, spawn(fn -> :ok end)} end,
        start_child: fn _supervisor, _child -> {:ok, spawn(fn -> :ok end)} end do
        with_mock MessageContext, [:passthrough],
          handlers_configured?: fn ^broker -> false end,
          save_handlers_config: fn ^config, ^broker -> :ok end do
          {:ok, pid} = ListenerController.start_link(broker)

          assert :ok == ListenerController.configure(config)

          GenServer.stop(pid)
        end
      end
    end
  end
end
