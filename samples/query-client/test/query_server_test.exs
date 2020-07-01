defmodule QueryServerTest do
  use ExUnit.Case
  doctest QueryServer

  test "greets the world" do
    assert QueryServer.hello() == :world
  end
end
