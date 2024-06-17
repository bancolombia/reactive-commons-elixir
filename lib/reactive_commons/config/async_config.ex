defmodule AsyncConfig do
  @moduledoc """
  Configuration structure for using reactive commons abstraction

  The required properties are:
  - application_name: "my_app"

  Optionally you can change the default values for another property
  ```elixir
  %{
    reply_exchange: "globalReply",
    direct_exchange: "directMessages",
    events_exchange: "domainEvents",
    connection_props: "amqp://guest:guest@localhost", this value is passed as uri_or_options in https://hexdocs.pm/amqp/AMQP.Connection.html#open/1
    connection_assignation: %{
      ReplyListener: ListenerConn,
      QueryListener: ListenerConn,
      CommandListener: ListenerConn,
      EventListener: ListenerConn,
      NotificationEventListener: ListenerConn,
      MessageExtractor: ListenerConn,
      MessageSender: SenderConn,
      ListenerController: SenderConn,
    },
    topology: %{
      command_sender: false,
      queries_sender: false,
      events_sender: false
    },
    queries_reply: true,
    with_dlq_retry: false,
    retry_delay: 500,
    max_retries: 10,
    prefetch_count: 250,
  }
  ```
  """

  defstruct [
    :application_name,
    :reply_queue,
    :query_queue,
    :command_queue,
    :event_queue,
    :notification_event_queue,
    :reply_exchange,
    :direct_exchange,
    :reply_routing_key,
    :connection_assignation,
    :topology,
    :queries_reply,
    :connection_props,
    :with_dlq_retry,
    :retry_delay,
    :max_retries,
    :prefetch_count,
    extractor_debug: false
  ]

  @doc """
  Creates a new default valued AsyncConfig struct with the specified app name.
  """
  def new(app_name) do
    %__MODULE__{application_name: app_name}
  end
end
