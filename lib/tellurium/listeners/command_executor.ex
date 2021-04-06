defmodule CommandExecutor do
  use GenericExecutor

  def get_handler_path(_,  %{"name" => handler_path}), do: handler_path

end
