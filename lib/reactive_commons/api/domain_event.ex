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


  def new(name, data) do
    new_p(name, data, NameGenerator.message_id())
  end

  def new(name, data, message_id) do
    new_p(name, data, message_id)
  end

  defp new_p(nil, _, _), do: raise "Invalid nil values in DomainEvent constructor!"
  defp new_p(_, nil, _), do: raise "Invalid nil values in DomainEvent constructor!"
  defp new_p(_, _, nil), do: raise "Invalid nil values in DomainEvent constructor!"
  defp new_p(name, data, message_id) do
    %__MODULE__{
      name: name,
      data: data,
      eventId: message_id
    }
  end



end
