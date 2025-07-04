defmodule SafeAtomTest do
  use ExUnit.Case

  test "should return existing atom" do
    expected = :existing_atom
    existing = SafeAtom.to_atom("existing_atom")

    assert expected == existing
  end

  test "should return new atom" do
    result = SafeAtom.to_atom("no_existing_atom")

    assert is_atom(result)
  end
end
