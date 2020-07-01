defmodule AsyncQuery do
  defstruct [:resource, :queryData]

  def new(resource, data) do
    %__MODULE__{resource: resource, queryData: data}
  end

end
