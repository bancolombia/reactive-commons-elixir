import Config

config :query_server,
       async_config: %{
         application_name: "sample-query-server",
         queries_reply: true
       }
