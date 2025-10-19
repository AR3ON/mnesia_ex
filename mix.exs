defmodule MnesiaEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/AR3ON/mnesia_ex"

  def project do
    [
      app: :mnesia_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "MnesiaEx",
      source_url: @source_url,
      homepage_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {MnesiaEx.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:csv, "~> 3.0"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    A functional, monadic wrapper for Mnesia built with category theory principles.
    Features: auto-increment counters, TTL with automatic cleanup, backup/restore,
    real-time events, and a clean CRUD API. Pure functional programming throughout.
    """
  end

  defp package do
    [
      name: :mnesia_ex,
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/mnesia_ex"
      },
      maintainers: ["AR3ON"],
      keywords: [
        "mnesia",
        "database",
        "distributed",
        "functional",
        "monad",
        "ttl",
        "backup",
        "counter",
        "events",
        "category-theory"
      ]
    ]
  end

  defp docs do
    [
      main: "MnesiaEx",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "examples/README.md"
      ],
      groups_for_extras: [
        Introduction: ~r/README.md/,
        Examples: ~r/examples\//,
        Changelog: ~r/CHANGELOG.md/,
        License: ~r/LICENSE/
      ],
      groups_for_modules: [
        "Core API": [
          MnesiaEx,
          MnesiaEx.Application
        ],
        "Database Operations": [
          MnesiaEx.Schema,
          MnesiaEx.Table,
          MnesiaEx.Query
        ],
        "Features": [
          MnesiaEx.TTL,
          MnesiaEx.Counter,
          MnesiaEx.Events,
          MnesiaEx.Backup
        ],
        "Utilities": [
          MnesiaEx.Config,
          MnesiaEx.Utils,
          MnesiaEx.Duration
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
