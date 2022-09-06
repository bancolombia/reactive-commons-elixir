defmodule ReactiveCommonsSetup do
  @doc """
  Get config of type AsyncConfig.
  """
  @callback config() :: map()

  defmacro __using__(opts) do
    quote do
      use Supervisor

      def start_link(args) do
        Supervisor.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(_args) do
        conn_config = config() |> merge()
        subs_config = handlers_config()
        children = [
          {MessageRuntime, conn_config},
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
      defp handlers_config(), do: %HandlersConfig{}

      defoverridable handlers_config: 0
    end
  end
end
