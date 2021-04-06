defmodule AsyncConfig do
  defstruct [
    :application_name,
    :reply_queue,
    :query_queue,
    :command_queue,
    :event_queue,
    :reply_exchange,
    :direct_exchange,
    :reply_routing_key,
    :connection_assignation,
    :connection_props,
    :with_dlq_retry,
    :retry_delay,
    :max_retries,
    extractor_debug: false
  ]

  def new(app_name) do
    %__MODULE__{application_name: app_name}
  end

end
