defmodule HandlerRegistry do
  @moduledoc """
  This module allows the subscription for events, commands and async queries and for registering their respective handlers.
  """
  alias HandlersConfig, as: Conf

  def serve_query(path, handler), do: serve_query(:app, path, handler)

  def serve_query(broker, path, handler) when not is_struct(broker),
    do: Conf.new(broker) |> Conf.add_listener(:query_listeners, path, handler)

  def serve_query(conf = %Conf{}, path, handler),
    do: Conf.add_listener(conf, :query_listeners, path, handler)

  def handle_command(path, handler), do: handle_command(:app, path, handler)

  def handle_command(broker, path, handler) when not is_struct(broker),
    do: Conf.new(broker) |> Conf.add_listener(:command_listeners, path, handler)

  def handle_command(conf = %Conf{}, path, handler),
    do: Conf.add_listener(conf, :command_listeners, path, handler)

  def listen_event(path, handler), do: listen_event(:app, path, handler)

  def listen_event(broker, path, handler) when not is_struct(broker),
    do: Conf.new(broker) |> Conf.add_listener(:event_listeners, path, handler)

  def listen_event(conf = %Conf{}, path, handler),
    do: Conf.add_listener(conf, :event_listeners, path, handler)

  def listen_notification_event(path, handler), do: listen_notification_event(:app, path, handler)

  def listen_notification_event(broker, path, handler) when not is_struct(broker),
    do: Conf.new(broker) |> Conf.add_listener(:notification_event_listeners, path, handler)

  def listen_notification_event(conf = %Conf{}, path, handler),
    do: Conf.add_listener(conf, :notification_event_listeners, path, handler)

  def commit_config(conf = %Conf{}), do: ListenerController.configure(conf)
end
