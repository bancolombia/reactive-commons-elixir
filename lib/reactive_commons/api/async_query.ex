defmodule AsyncQuery do
  @moduledoc """
  Queries represent a intention for getting information about something, that query must to be processed by the domain
  context with that responsibility and that context must respond with the information requested throught request/reply
  pattern. An example of a query may be: "UserInfo".
  """

  defstruct [:resource, :queryData]

  @doc """
  Creates a new AsyncQuery structure

  ## Examples

      iex> AsyncQuery.new("UserInfo", %{name: "username"})
      %AsyncQuery{queryData: %{name: "username"}, resource: "UserInfo"}
  """
  def new(resource, data), do: new_p(resource, data)

  defp new_p(nil, _), do: raise "Invalid nil name in AsyncQuery constructor!"
  defp new_p(_, nil), do: raise "Invalid nil data in AsyncQuery constructor!"
  defp new_p(name, data) do
    %__MODULE__{
      resource: name,
      queryData: data
    }
  end

end
