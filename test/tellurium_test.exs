defmodule TelluriumTest do
  use ExUnit.Case
  doctest Tellurium

  test "greets the world" do
    assert Tellurium.hello() == :world
  end
end
