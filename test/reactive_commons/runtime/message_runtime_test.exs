defmodule MessageRuntimeTest do
  use ExUnit.Case

  setup_all do
    Application.put_env(:message_runtime_test, :dummy_config, true)
    :ok
  end

  describe "start_link/1 and init/1" do
    test "starts the supervisor with config as map of one broker" do
      conf = %{broker1: %{application_name: "sample-broker1"}}
      {:ok, pid} = MessageRuntime.start_link(conf)
      assert is_pid(pid)
      assert Process.alive?(pid)
      close_process(pid)
    end

    test "starts the supervisor with config as map of multiple brokers" do
      conf = %{
        broker2: %{application_name: "sample-broker2"},
        broker3: %{application_name: "sample-broker3"}
      }

      {:ok, pid} = MessageRuntime.start_link(conf)
      assert is_pid(pid)
      assert Process.alive?(pid)
      close_process(pid)
    end

    test "starts the supervisor with AsyncConfig struct and extractor debug true" do
      conf = %AsyncConfig{application_name: "sample-app", extractor_debug: true}
      {:ok, pid} = MessageRuntime.start_link(conf)
      assert is_pid(pid)
      assert Process.alive?(pid)
      close_process(pid)
    end

    test "starts the supervisor with AsyncConfig struct and extractor debug false" do
      conf = %AsyncConfig{application_name: "sample-app"}
      {:ok, pid} = MessageRuntime.start_link(conf)
      assert is_pid(pid)
      assert Process.alive?(pid)
      close_process(pid)
    end

    defp close_process(pid) do
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)
    end
  end
end
