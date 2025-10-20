import Config

config :query_server,
  async_config: %{
    app: %{
      application_name: "sample-query-server",
      queries_reply: true,
      max_retries: 1
    },
    app2: %{
      application_name: "sample-query-server-2",
      queries_reply: true,
      max_retries: 5
    }
  }
