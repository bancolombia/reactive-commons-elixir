defmodule DomainEvent do
  @moduledoc """
    Events represent a fact inside the domain, it is the representation of a decision or a state change that a system want
    to notify to its subscribers. Events represents facts that nobody can change, so events are not intentions or requests
    of anything, An example may be and UserRegistered or a NotificationSent.

    Events are the most important topic in a Publish-Subscribe system, because this element let’s notify a many
    stakeholders in a specific event. An other benefit is the system is decouple, because you can add more subscriber to
    the system without modify some component.
  """

  defstruct [
    :name,
    :eventId,
    :data
  ]

  @doc """
  Creates a new DomainEvent structure with a generated event_id

  ## Examples

      iex> DomainEvent.new("UserRegistered", %{name: "username", email: "user@example.com", createdAt: "2021-05-11T15:00:47.380Z"})
      %DomainEvent{
        data: %{
          createdAt: "2021-05-11T15:00:47.380Z",
          email: "user@example.com",
          name: "username"
        },
        eventId: "852e6f59-f920-45e0-bce8-75f1e74647ff",
        name: "UserRegistered"
      }
  """
  def new(name, data) do
    new_p(name, data, NameGenerator.message_id())
  end

  @doc """
  Creates a new DomainEvent structure

  ## Examples

      iex> DomainEvent.new("UserRegistered", %{name: "username", email: "user@example.com", createdAt: "2021-05-11T15:00:47.380Z"}, "852e6f59-f920-45e0-bce8-75f1e74647aa")
      %DomainEvent{
        data: %{
          createdAt: "2021-05-11T15:00:47.380Z",
          email: "user@example.com",
          name: "username"
        },
        eventId: "852e6f59-f920-45e0-bce8-75f1e74647aa",
        name: "UserRegistered"
      }
  """
  def new(name, data, event_id), do: new_p(name, data, event_id)

  defp new_p(nil, _, _), do: raise("Invalid nil name in DomainEvent constructor!")
  defp new_p(_, nil, _), do: raise("Invalid nil data in DomainEvent constructor!")
  defp new_p(_, _, nil), do: raise("Invalid nil event_id in DomainEvent constructor!")

  defp new_p(name, data, event_id) do
    %__MODULE__{
      name: name,
      data: data,
      eventId: event_id
    }
  end
end
