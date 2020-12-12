defmodule Command do
  defstruct [:name, :commandId, :data]

  def new(name, command_id, data) do
    %__MODULE__{name: name, commandId: command_id, data: data}
  end

end
