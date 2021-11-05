defmodule ListenersValidator do

  def should_listen_events(%HandlersConfig{event_listeners: event_listeners})
      when map_size(event_listeners) > 0, do: true
  def should_listen_events(_), do: false

  def should_listen_commands(%HandlersConfig{command_listeners: command_listeners})
      when map_size(command_listeners) > 0, do: true
  def should_listen_commands(_), do: false

  def should_listen_queries(%HandlersConfig{query_listeners: query_listeners})
      when map_size(query_listeners) > 0, do: true
  def should_listen_queries(_), do: false

  def should_listen_replies(%AsyncConfig{queries_reply: true}), do: true
  def should_listen_replies(_), do: false

end
