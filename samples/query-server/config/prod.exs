import Config

config :query_server,
       async_config: %{
         application_name: "sample-query-server",
         connection_props: "amqp://guest:guest@localhost",
       }
