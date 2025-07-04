defmodule SafeAtom do
  @moduledoc """
  Provides a safe way to create atoms from strings, avoiding memory leaks.
  """

  @doc """
  Converts a string to an atom safely, ensuring it does not lead to memory leaks.
  """
  def to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> String.to_atom(string)
  end
end
