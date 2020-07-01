defmodule MessageHeaders do

  def h_REPLY_ID, do: "x-reply_id"
  def h_CORRELATION_ID, do: "x-correlation-id"
  def h_COMPLETION_ONLY_SIGNAL, do: "x-empty-completion"
  def h_SERVED_QUERY_ID, do: "x-serveQuery-id"
  def h_SOURCE_APPLICATION, do: "sourceApplication"
  def h_SIGNAL_TYPE, do: "x-signal-type"

end