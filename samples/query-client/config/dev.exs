import Config

config :query_client,
  async_config: %{
    app: %{
      application_name: "sample-query-client",
      topology: %{
        command_sender: true,
        queries_sender: true,
        events_sender: true
      }
    },
    app2: %{
      application_name: "sample-query-client-2",
      topology: %{
        command_sender: true,
        queries_sender: true,
        events_sender: true
      }
    }
  },
  http_port: 4001
