import Config

config :query_client,
       async_config: %{
         application_name: "sample-query-client"
       },
       http_port: 4001
