defmodule MessageHeaders do
  @moduledoc false
  def h_reply_id, do: "x-reply_id"
  def h_correlation_id, do: "x-correlation-id"
  def h_completion_only_signal, do: "x-empty-completion"
  def h_served_query_id, do: "x-serveQuery-id"
  def h_source_application, do: "sourceApplication"
  def h_signal_type, do: "x-signal-type"
  def h_x_death, do: "x-death"
  def h_x_death_count, do: "count"
end
