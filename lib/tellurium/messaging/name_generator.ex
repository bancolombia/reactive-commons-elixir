defmodule NameGenerator do

  def generate() do
    UUID.uuid4(:hex)
  end

  def message_id, do: UUID.uuid4()

  def generate(prefix) do
    name = "#{prefix}-#{UUID.uuid4() |> String.replace("-", "")}"
  end

end
