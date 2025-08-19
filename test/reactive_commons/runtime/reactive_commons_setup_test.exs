defmodule ReactiveCommonsSetupTest do
  use ExUnit.Case
  import Mock

  defmodule TestSetup do
    use ReactiveCommonsSetup

    @impl true
    def config do
      %{}
    end
  end

  describe "ReactiveCommonsSetup.init/1" do
    test "init with single broker config" do
      defmodule SingleBrokerSetup do
        use ReactiveCommonsSetup

        @impl true
        def config do
          %{application_name: "test1"}
        end
      end

      {:ok, sup} = SingleBrokerSetup.start_link([])
      children = Supervisor.which_children(sup)

      assert Enum.any?(children, fn
               {MessageRuntime, _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(children, fn
               {{:subs_config, :app}, _, _, _} -> true
               _ -> false
             end)
    end

    test "init with multi broker config" do
      defmodule MultiBrokerSetup do
        use ReactiveCommonsSetup

        @impl true
        def config do
          %{
            broker1: %{application_name: "test1"},
            broker2: %{application_name: "test2"}
          }
        end
      end

      {:ok, sup} = MultiBrokerSetup.start_link([])
      children = Supervisor.which_children(sup)

      assert Enum.any?(children, fn
               {MessageRuntime, _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(children, fn
               {{:subs_config, :broker1}, _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(children, fn
               {{:subs_config, :broker2}, _, _, _} -> true
               _ -> false
             end)
    end
  end
end
