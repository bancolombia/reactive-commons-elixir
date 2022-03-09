defmodule NameGeneratorTest do
  use ExUnit.Case

  test "should generate a name" do
    result = NameGenerator.generate()
    assert 32 == String.length(result)
  end

  test "should generate a message id" do
    result = NameGenerator.message_id()
    assert 36 == String.length(result)
  end

  test "should generate a name with custom prefix" do
    result = NameGenerator.generate("app", "reply")
    assert String.starts_with?(result, "app-reply")
  end

end
