import Config

config :query_client,
       async_config: %{
         application_name: "sample-query-client",
         connection_props: "amqp://guest:guest@localhost",
       },
       http_port: 4001
