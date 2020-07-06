defmodule Tellurium.MixProject do
  use Mix.Project

  def project do
    [
      app: :tellurium,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
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
      {:poison, "~> 4.0"},
      {:amqp, "~> 1.4"},
      {:uuid, "~> 1.1"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README", "LICENSE*"],
      maintainers: ["Daniel Bustamante Ospina"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/dbuos/tellurium"}
    ]
  end

end
