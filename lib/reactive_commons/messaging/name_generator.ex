defmodule NameGenerator do
  @moduledoc """
    This module generates unique identifiers for temporary queue names, message ids and routing keys.
  """

  @doc """
  Generate an hex unique random id.
  ## Examples
  ```elixir
  iex> NameGenerator.generate()
  "fb49a0ecd60c4d2092643b4cfe272106"
  ```
  """
  def generate do
    UUID.uuid4(:hex)
  end

  @doc """
  Generate a new id using UUID v4.
  ## Examples
  ```elixir
  iex> NameGenerator.message_id()
  "fb49a0ec-d60c-4d20-9264-3b4cfe272106"
  ```
  """
  def message_id, do: UUID.uuid4()

  @doc """
  Generate a new id using UUID v4 with a fixed prefix.
  ## Examples
  ```elixir
  iex> NameGenerator.generate("sample_app")
  "sample_app-fb49a0ecd60c4d2092643b4cfe272106"
  ```
  """
  def generate(app, prefix) do
    "#{app}-#{prefix}-#{UUID.uuid4() |> String.replace("-", "")}"
  end
end
