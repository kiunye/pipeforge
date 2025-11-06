# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pipeforge,
  namespace: PipeForge,
  ecto_repos: [PipeForge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :pipeforge, PipeForgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PipeForgeWeb.ErrorHTML, json: PipeForgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PipeForge.PubSub,
  live_view: [signing_salt: "+pM1txIj"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pipeforge: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  pipeforge: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban for background jobs
config :pipeforge, Oban,
  engine: Oban.Engines.Basic,
  queues: [rollups: 10, alerts: 5, default: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Run daily rollups at 2 AM UTC (after midnight data is complete)
       {"0 2 * * *", PipeForge.Rollups.DailyRollupWorker, args: %{}},
       # Run sales alerts at 2:30 AM UTC (after rollups complete)
       {"30 2 * * *", PipeForge.Alerts.SalesAlertWorker, args: %{}}
     ]},
    Oban.Plugins.Pruner
  ]

# Configure Swoosh for email alerts
config :pipeforge, PipeForge.Alerts.EmailNotifier,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("SMTP_HOST") || "localhost",
  port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
  username: System.get_env("SMTP_USERNAME"),
  password: System.get_env("SMTP_PASSWORD"),
  ssl: true,
  tls: :if_available,
  auth: :always,
  retries: 2

# Alert configuration
config :pipeforge,
  slack_webhook_url: System.get_env("SLACK_WEBHOOK_URL"),
  alert_email_recipients: System.get_env("ALERT_EMAIL_RECIPIENTS"),
  alert_from_email: System.get_env("ALERT_FROM_EMAIL") || "alerts@pipeforge.com"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
