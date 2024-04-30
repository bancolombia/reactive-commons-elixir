defmodule OutMessage do
  @moduledoc false
  defstruct headers: [],
            content_encoding: "UTF-8",
            content_type: "application/json",
            persistent: true,
            exchange_name: nil,
            routing_key: nil,
            payload: nil

  def new(props) do
    struct(__MODULE__, props)
  end
end
