defmodule ReactiveCommons.MixProject do
  use Mix.Project

  @version "0.8.5"

  def project do
    [
      app: :reactive_commons,
      version: @version,
      elixir: "~> 1.13",
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}"
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      source_url: "https://github.com/bancolombia/reactive-commons-elixir"
    ]
  end

  defp description() do
    "Domain driven async abstractions like Domain Event Bus, Event subscriptions/emit, Async Command handling and Async Req/Reply."
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      {:poison, "~> 5.0"},
      {:amqp, "~> 3.3"},
      {:uuid, "~> 1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:telemetry, "~> 1.2"},
      {:mock, "~> 0.3", only: :test}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Daniel Bustamante Ospina"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/bancolombia/reactive-commons-elixir",
        "About this initiative" => "https://reactivecommons.org"
      }
    ]
  end

end
