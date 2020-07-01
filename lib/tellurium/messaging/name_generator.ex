defmodule NameGenerator do

  def generate() do
    UUID.uuid4(:hex)
  end

  def generate(prefix) do
    name = "#{prefix}-#{UUID.uuid4() |> String.replace("-", "")}"
  end

end
