defmodule MessageToHandle do
  @moduledoc false
  @type t :: %__MODULE__{
          delivery_tag: String.t(),
          redelivered: term(),
          headers: term(),
          payload: term(),
          chan: AMQP.Channel.t(),
          handlers_ref: term(),
          meta: term()
        }

  defstruct [
    :delivery_tag,
    :redelivered,
    :headers,
    :payload,
    :chan,
    :handlers_ref,
    :meta
  ]

  def new(
        meta = %{delivery_tag: tag, redelivered: redelivered, headers: headers},
        payload,
        chan,
        handlers_ref
      ) do
    %__MODULE__{
      delivery_tag: tag,
      redelivered: redelivered,
      headers: headers,
      payload: payload,
      chan: chan,
      handlers_ref: handlers_ref,
      meta: meta
    }
  end
end
