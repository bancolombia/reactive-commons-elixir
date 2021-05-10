defmodule HandlerRegistry do

  alias HandlersConfig, as: Conf

  def serve_query(path, handler), do: Conf.new() |> serve_query(path, handler)
  def serve_query(conf = %Conf{}, path, handler), do: conf |> Conf.add_listener(:query_listeners, path, handler)

  def handle_command(path, handler), do: Conf.new() |> handle_command(path, handler)
  def handle_command(conf = %Conf{}, path, handler), do: conf |> Conf.add_listener(:command_listeners, path, handler)

  def listen_event(path, handler), do: Conf.new() |> listen_event(path, handler)
  def listen_event(conf = %Conf{}, path, handler), do: conf |> Conf.add_listener(:event_listeners, path, handler)

  def commit_config(conf = %Conf{}) do
    ListenerController.configure(conf)
  end


end
