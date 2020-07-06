defmodule Tellurium do
  @moduledoc """
  Documentation for `Tellurium`.
  """

  @doc """
  Hello world.

  ## Examples

    query = AsyncQuery.new("query_path", %{field: "value", field_n: 42})
    {:ok, response} = DirectAsyncGateway.request_reply_wait(query, @target)

  """
  def hello do
    :world
  end
end
