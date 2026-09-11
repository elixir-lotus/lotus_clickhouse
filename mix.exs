defmodule Lotus.ClickHouse.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-lotus/lotus_clickhouse"
  @version "1.0.0"

  def project do
    [
      app: :lotus_clickhouse,
      name: "Lotus ClickHouse",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      package: package(),
      description: description(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [preferred_envs: ["test.setup": :test, test: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:lotus, "~> 1.0.0-rc.1"},
      {:ecto_ch, "~> 0.3"},
      {:ecto_sqlite3, "~> 0.21", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.setup": ["cmd docker compose up -d"],
      lint: ["format", "dialyzer"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "_build/#{Mix.env()}",
      flags: [:error_handling, :missing_return, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/installation.md",
        "guides/how-it-works.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Adapter: [
          Lotus.Source.Adapters.ClickHouse,
          Lotus.Source.Adapters.Ecto.Dialects.ClickHouse
        ]
      ]
    ]
  end

  defp package do
    [
      name: "lotus_clickhouse",
      maintainers: ["Arda Can Tugay", "Rui Freitas"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url},
      files: ~w[lib guides .formatter.exs mix.exs README* CHANGELOG* LICENSE*]
    ]
  end

  defp description do
    "ClickHouse source adapter for Lotus — run Lotus queries, dashboards, and AI-assisted exploration against ClickHouse clusters."
  end
end
