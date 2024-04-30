defmodule CommandExecutor do
  @moduledoc false
  use GenericExecutor, type: :command

  def get_handler_path(_, %{"name" => handler_path}), do: handler_path
end
