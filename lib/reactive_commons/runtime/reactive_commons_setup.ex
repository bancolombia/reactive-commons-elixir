defmodule ReactiveCommonsSetup do
  @doc """
  Get config of type AsyncConfig.
  """
  @moduledoc false
  @callback config(broker :: atom()) :: map()

  defmacro __using__(_opts) do
    quote do
      use Supervisor

      def start_link(broker) when is_atom(broker) do
        Supervisor.start_link(__MODULE__, broker,
          name: SafeAtom.to_atom("reactive_commons_setup_#{broker}")
        )
      end

      @impl true
      def init(broker) do
        conn_config = config(broker) |> merge()
        subs_config = handlers_config(broker)

        children = [
          {MessageRuntime, %{app: Map.from_struct(conn_config)}},
          {SubsConfigProcess, subs_config}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp merge(params) when is_map(params) do
        Application.get_application(__MODULE__)
        |> Atom.to_string()
        |> AsyncConfig.new()
        |> Map.merge(params)
      end

      @doc """
      Get config of type HandlersConfig.
      """
      defp handlers_config(broker), do: %HandlersConfig{broker: broker}

      defoverridable handlers_config: 1
    end
  end
end
