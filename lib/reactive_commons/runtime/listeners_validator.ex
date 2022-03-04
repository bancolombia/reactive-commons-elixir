defmodule ListenersValidator do

  def has_handlers(handlers = %{})
      when map_size(handlers) > 0, do: true
  def has_handlers(_), do: false

  def should_listen_replies(%AsyncConfig{queries_reply: true}), do: true
  def should_listen_replies(_), do: false

end
