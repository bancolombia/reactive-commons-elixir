defmodule Command do
  @moduledoc """
    Commands represent a intention for doing something, that intention must to be done by the domain context with that
    responsibility. An example of a command may be: "RegisterUser" or "SendNotification".
  """

  defstruct [:name, :commandId, :data]

  @doc """
  Creates a new Command structure with a generated command_id

  ## Examples

      iex> Command.new("RegisterUser", %{name: "username", email: "user@example.com"})
      %Command{
        commandId: "a313623c-4701-40d3-95e0-bde25e02b52a",
        data: %{email: "user@example.com", name: "username"},
        name: "registerUser"
      }
  """
  def new(name, data) do
    new_p(name, data, NameGenerator.message_id())
  end

  @doc """
  Creates a new Command structure

  ## Examples

      iex> Command.new("RegisterUser", %{name: "username", email: "user@example.com"}, "4016ab59-16d0-41cd-ba4f-52ce200f8ea8")
      %Command{
        commandId: "4016ab59-16d0-41cd-ba4f-52ce200f8ea8",
        data: %{email: "user@example.com", name: "username"},
        name: "registerUser"
      }
  """
  def new(name, data, command_id), do: new_p(name, data, command_id)

  defp new_p(nil, _, _), do: raise("Invalid nil name in Command constructor!")
  defp new_p(_, nil, _), do: raise("Invalid nil data in Command constructor!")
  defp new_p(_, _, nil), do: raise("Invalid nil command_id in Command constructor!")

  defp new_p(name, data, command_id) do
    %__MODULE__{
      name: name,
      data: data,
      commandId: command_id
    }
  end
end
