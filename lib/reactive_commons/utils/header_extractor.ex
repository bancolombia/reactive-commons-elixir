defmodule HeaderExtractor do

  def get_x_death_count(headers) do
    case get_header_value(headers, MessageHeaders.h_X_DEATH()) do
      nil -> 0
      [ {_, sub_h} | _] -> get_header_value(sub_h, MessageHeaders.h_X_DEATH_COUNT(), 0)
    end
  end

  def get_header_value(headers, name, default \\ nil) do
    case headers |> Enum.find(match_header(name)) do
      nil -> default
      e -> elem(e, 2)
    end
  end

  defp match_header(name) do
    fn
      {^name, _, _} -> true
      _ -> false
    end
  end

end
