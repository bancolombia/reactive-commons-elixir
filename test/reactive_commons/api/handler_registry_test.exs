defmodule HandlerRegistryTest do
  use ExUnit.Case
  import Mock

  alias HandlerRegistry
  alias HandlersConfig, as: Conf

  describe "serve_query/3" do
    test "calls Conf.new and Conf.add_listener with correct params" do
      with_mocks([
        {Conf, [:passthrough],
         [
           new: fn :app -> %Conf{broker: :app} end,
           add_listener: fn %Conf{} = conf, :query_listeners, "path", :handler ->
             {:ok, conf, :query}
           end
         ]}
      ]) do
        assert HandlerRegistry.serve_query("path", :handler) == {:ok, %Conf{broker: :app}, :query}

        assert_called(Conf.new(:app))
        assert_called(Conf.add_listener(%Conf{broker: :app}, :query_listeners, "path", :handler))
      end
    end
  end

  describe "handle_command/3" do
    test "delegates command handling to Conf" do
      with_mocks([
        {Conf, [:passthrough],
         [
           new: fn :custom -> %Conf{broker: :custom} end,
           add_listener: fn %Conf{} = conf, :command_listeners, "cmd.path", :cmd_handler ->
             {:ok, conf, :command}
           end
         ]}
      ]) do
        assert HandlerRegistry.handle_command(:custom, "cmd.path", :cmd_handler) ==
                 {:ok, %Conf{broker: :custom}, :command}

        assert_called(Conf.new(:custom))

        assert_called(
          Conf.add_listener(%Conf{broker: :custom}, :command_listeners, "cmd.path", :cmd_handler)
        )
      end
    end
  end

  describe "listen_event/3" do
    test "adds event listener" do
      with_mocks([
        {Conf, [:passthrough],
         [
           new: fn :some_app -> %Conf{broker: :some_app} end,
           add_listener: fn %Conf{} = conf, :event_listeners, "evt", :evt_handler ->
             {:ok, conf, :event}
           end
         ]}
      ]) do
        assert HandlerRegistry.listen_event(:some_app, "evt", :evt_handler) ==
                 {:ok, %Conf{broker: :some_app}, :event}

        assert_called(Conf.new(:some_app))

        assert_called(
          Conf.add_listener(%Conf{broker: :some_app}, :event_listeners, "evt", :evt_handler)
        )
      end
    end
  end

  describe "listen_notification_event/3" do
    test "adds notification event listener" do
      with_mocks([
        {Conf, [:passthrough],
         [
           new: fn _ -> %Conf{broker: :app} end,
           add_listener: fn %Conf{} = conf, :notification_event_listeners, "notif", :handler ->
             {:ok, conf, :notif}
           end
         ]}
      ]) do
        assert HandlerRegistry.listen_notification_event("notif", :handler) ==
                 {:ok, %Conf{broker: :app}, :notif}

        assert_called(
          Conf.add_listener(%Conf{broker: :app}, :notification_event_listeners, "notif", :handler)
        )
      end
    end
  end

  describe "commit_config/1" do
    test "calls ListenerController.configure/1" do
      with_mocks([
        {ListenerController, [],
         [
           configure: fn %Conf{} = conf -> {:configured, conf} end
         ]}
      ]) do
        conf = %Conf{}
        assert HandlerRegistry.commit_config(conf) == {:configured, conf}
        assert_called(ListenerController.configure(conf))
      end
    end
  end
end
