defmodule TopologyUtils do
  @moduledoc false

  def set_queue_type(args, _queue_type = nil), do: args

  def set_queue_type(args, queue_type) do
    [{"x-queue-type", :longstr, queue_type} | args]
  end
end
