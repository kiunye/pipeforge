defmodule PipeForge.MixProject do
  use Mix.Project

  def project do
    [
      app: :pipeforge,
      version: "0.1.0",
      elixir: "~> 1.18.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PipeForge.Application, []},
      extra_applications: [:logger, :runtime_tools, :ecto, :ecto_sql]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2"},
      {:bandit, "~> 1.8"},
      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.21"},
      # Queue & Workers
      {:broadway, "~> 1.2"},
      {:broadway_rabbitmq, "~> 0.8"},
      {:amqp, "~> 4.1"},
      # Background Jobs
      {:oban, "~> 2.20"},
      # OAuth
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_github, "~> 0.8"},
      # JWT
      {:joken, "~> 2.6"},
      # MinIO/S3
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.25"},
      {:sweet_xml, "~> 0.7"},
      # CSV parsing
      {:nimble_csv, "~> 1.2"},
      # BigQuery
      {:google_api_big_query, "~> 0.88"},
      {:goth, "~> 1.4"},
      # Code Quality & Security
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind pipeforge", "esbuild pipeforge"],
      "assets.deploy": [
        "tailwind pipeforge --minify",
        "esbuild pipeforge --minify",
        "phx.digest"
      ],
      precommit: [
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "sobelow --config",
        "test"
      ]
    ]
  end
end
