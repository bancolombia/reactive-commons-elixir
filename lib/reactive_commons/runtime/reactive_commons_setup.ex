defmodule ReactiveCommonsSetup do
  @doc """
  Get config of type AsyncConfig.
  """
  @moduledoc false
  @callback config() :: map()

  defmacro __using__(_opts) do
    quote do
      use Supervisor

      def start_link(args) do
        Supervisor.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(args) do
        raw_config = config()

        is_multi_broker? =
          is_map(raw_config) and
            map_size(raw_config) > 0 and
            Enum.all?(Map.values(raw_config), &is_map/1)

        {conn_configs, subs_configs} =
          if is_multi_broker? do
            conn_configs =
              Enum.into(raw_config, %{}, fn {broker, broker_cfg} ->
                {broker, merge(broker, broker_cfg)}
              end)

            subs_configs =
              Enum.into(conn_configs, %{}, fn {broker, async_cfg} ->
                {broker, handlers_config(async_cfg)}
              end)

            {conn_configs, subs_configs}
          else
            async_cfg = merge(:app, raw_config)
            handlers_cfg = handlers_config(async_cfg)
            {%{app: async_cfg}, %{app: handlers_cfg}}
          end

        children =
          [
            {MessageRuntime, conn_configs}
          ] ++
            Enum.map(subs_configs, fn {broker, broker_cfg} ->
              Supervisor.child_spec({SubsConfigProcess, broker_cfg}, id: {:subs_config, broker})
            end)

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp merge(broker, broker_cfg) when is_map(broker_cfg) do
        app_name =
          Application.get_application(__MODULE__)
          |> Atom.to_string()

        AsyncConfig.new(app_name)
        |> Map.merge(%{broker: broker})
        |> Map.merge(broker_cfg)
      end

      @doc """
      Get config of type HandlersConfig.
      """
      defp handlers_config(%AsyncConfig{broker: broker}) do
        %HandlersConfig{broker: broker}
      end

      defoverridable handlers_config: 1
    end
  end
end
