defmodule Command do
  @moduledoc """
  Commands represent a intention for doing something, that intention must to be done by the domain context with that
  responsibility. An example of a command may be: "registerUser" or "sendNotification".
  """

  defstruct [:name, :commandId, :data]

  def new(name, command_id, data) do
    %__MODULE__{name: name, commandId: command_id, data: data}
  end

end
