defmodule MessageToHandle do
  defstruct [
    :delivery_tag,
    :redelivered,
    :headers,
    :payload,
    :chan,
    :handlers_ref,
  ]

  def new(%{delivery_tag: tag, redelivered: redelivered, headers: headers}, payload, chan, handlers_ref) do
    %__MODULE__{
      delivery_tag: tag,
      redelivered: redelivered,
      headers: headers,
      payload: payload,
      chan: chan,
      handlers_ref: handlers_ref,
    }
  end

end
