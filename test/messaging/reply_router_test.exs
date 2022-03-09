defmodule ReplyRouterTest do
  use ExUnit.Case
  doctest ReplyRouter
  import Mock

  test "should send reply to the correct process" do
    # Arrange
    ReplyRouter.start_link(nil)
    task = Task.async(fn -> receive do any -> any end end) # Simulates process waiting for reply
    ReplyRouter.register_reply_route("uuid", task.pid)
    # Act
    result = ReplyRouter.route_reply("uuid", "message")
    # Assert
    reply = Task.await(task)
    assert {:reply, "uuid", "message"} == reply
    assert :ok == result
  end

  test "should ignore reply when no pending process registered" do
    # Arrange
    ReplyRouter.start_link(nil)
    # Act
    result = ReplyRouter.route_reply("uuid", "message")
    # Assert
    assert :no_route == result
  end

end
