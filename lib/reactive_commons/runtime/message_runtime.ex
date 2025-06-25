defmodule MessageRuntime do
  @moduledoc """
    This module initializes and supervises all required processes to enable the reactive commons ecosystem
  """
  use Supervisor

  def start_link(init_args) when is_map(init_args) do
    normalized_config = normalize_config(init_args)
    Supervisor.start_link(__MODULE__, normalized_config, name: __MODULE__)
  end

  @impl true
  def init(config_map) do
    children =
      Enum.map(config_map, fn {broker, conf_map} ->
        full_config = struct(AsyncConfig, Map.put(conf_map, :broker, broker))

        Supervisor.child_spec(
          {MessageRuntime.BrokerRuntime, full_config},
          id: {:message_runtime, broker}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp normalize_config(%AsyncConfig{} = conf) do
    %{app: Map.from_struct(conf)}
  end

  defp normalize_config(%{} = config_map) do
    if Enum.all?(config_map, fn {_k, v} -> is_map(v) end) do
      config_map
    else
      %{app: config_map}
    end
  end

  defmodule BrokerRuntime do
    @moduledoc false
    use Supervisor

    def start_link(config = %{broker: broker}) do
      name = :"message_runtime_#{broker}"
      Supervisor.start_link(__MODULE__, config, name: name)
    end

    @impl true
    def init(config = %{broker: broker, extractor_debug: true}) do
      children = [
        Supervisor.child_spec({MessageContext, config}, id: :"msg_ctx_#{broker}"),
        Supervisor.child_spec({ConnectionsHolder, broker}, id: :"connections_holder_#{broker}"),
        Supervisor.child_spec({MessageExtractor, broker}, id: :"message_extractor_#{broker}")
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end

    @impl true
    def init(config = %{broker: broker}) do
      children = [
        Supervisor.child_spec({MessageContext, config}, id: :"msg_ctx_#{broker}"),
        Supervisor.child_spec({ConnectionsHolder, broker}, id: :"connections_holder_#{broker}"),
        Supervisor.child_spec({ReplyRouter, broker}, id: :"reply_router_#{broker}"),
        Supervisor.child_spec({ReplyListener, broker}, id: :"reply_listener_#{broker}"),
        Supervisor.child_spec({MessageSender, broker}, id: :"message_sender_#{broker}"),
        Supervisor.child_spec({ListenerController, broker}, id: :"listener_controller_#{broker}")
      ]

      Supervisor.init(children, strategy: :rest_for_one)
    end
  end
end
