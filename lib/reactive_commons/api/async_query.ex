defmodule AsyncQuery do
  @moduledoc """
  Queries represent a intention for getting information about something, that query must to be processed by the domain
  context with that responsibility and that context must respond with the information requested throught request/reply
  pattern. An example of a query may be: "UserInfo".
  """

  defstruct [:resource, :queryData]

  def new(resource, data) do
    %__MODULE__{resource: resource, queryData: data}
  end

end
