defmodule ReactiveCommons.MixProject do
  use Mix.Project

  @version "1.1.0"

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
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        credo: :test,
        dialyzer: :test,
        sobelow: :test,
        coveralls: :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test
      ],
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
      {:poison, "~> 6.0 or ~> 5.0"},
      {:amqp, "~> 4.0 or ~> 3.3"},
      {:uuid, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # Tests and Analysis
      {:sobelow, "~> 0.13", [only: [:dev, :test]]},
      {:mock, "~> 0.3.8", [only: [:dev, :test]]},
      {:excoveralls, "~> 0.18", [only: [:dev, :test]]},
      {:git_hooks, "~> 0.7.3", [only: [:dev, :test], runtime: false]},
      {:credo, "~> 1.7", [only: [:dev, :test], runtime: false]},
      {:dialyxir, "~> 1.4", [only: [:dev, :test], runtime: false]}
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
