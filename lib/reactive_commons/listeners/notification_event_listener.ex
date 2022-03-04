defmodule NotificationEventListener do
  use GenericListener, handlers_table: :notification_event_handlers, executor: NotificationEventExecutor

  @impl true
  def should_listen(), do: ListenersValidator.has_handlers(get_handlers())

  def get_handlers(), do: MessageContext.handlers().notification_event_listeners

  @impl true
  def initial_state() do
    queue_name = MessageContext.notification_event_queue_name()
    prefetch_count = MessageContext.prefetch_count()
    %{prefetch_count: prefetch_count, queue_name: queue_name}
  end

  @impl true
  def create_topology(chan) do
    #Topology
    notification_event_queue_name = MessageContext.notification_event_queue_name()
    events_exchange_name = MessageContext.events_exchange_name()
    app_name = MessageContext.application_name()
    retry_delay = MessageContext.retry_delay()
    #Exchange
    :ok = AMQP.Exchange.declare(chan, events_exchange_name, :topic, durable: true)
    #Queue
    {:ok, _} = AMQP.Queue.declare(chan, notification_event_queue_name, auto_delete: true, exclusive: true)
    # Bindings
    for {event_name, _handler} <- :ets.tab2list(@handlers_table) do
      :ok = AMQP.Queue.bind(chan, notification_event_queue_name, events_exchange_name, routing_key: event_name)
    end
    :ok
  end

end
