defmodule ListenersValidatorTest do
  use ExUnit.Case

  test "should check if has registered handlers" do
    assert false == ListenersValidator.has_handlers(%{})
    assert false == ListenersValidator.has_handlers(nil)
    assert ListenersValidator.has_handlers(%{"event" => fn -> :ok end})
  end

  test "should check if param queries_reply is enabled" do
    assert false == ListenersValidator.should_listen_replies(%AsyncConfig{})
    assert false == ListenersValidator.should_listen_replies(nil)
    assert ListenersValidator.should_listen_replies(%AsyncConfig{queries_reply: true})
  end

end
