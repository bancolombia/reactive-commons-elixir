import Config

config :query_client,
       async_config: %{
         application_name: "sample-query-client",
         topology: %{
          command_sender: true,
          queries_sender: true,
          events_sender: true
        }
       },
       http_port: 4001
