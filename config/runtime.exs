import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pipeforge start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pipeforge, PipeForgeWeb.Endpoint, server: true
end

# Database configuration
# Only require DATABASE_URL in production
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://user:password@localhost/pipeforge_prod
      """

  config :pipeforge, PipeForge.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

# Configure Oban in production
if config_env() == :prod do
  config :pipeforge, Oban,
    engine: Oban.Engines.Basic,
    queues: [rollups: 10, alerts: 5, default: 10],
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {"0 2 * * *", PipeForge.Rollups.DailyRollupWorker, args: %{}},
         {"30 2 * * *", PipeForge.Alerts.SalesAlertWorker, args: %{}}
       ]},
      Oban.Plugins.Pruner
    ]

  # Configure Swoosh for email alerts in production
  config :pipeforge, PipeForge.Alerts.EmailNotifier,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_HOST") || raise "SMTP_HOST environment variable is required",
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    ssl: true,
    tls: :always,
    auth: :always,
    retries: 3

  # Alert configuration in production
  config :pipeforge,
    slack_webhook_url: System.get_env("SLACK_WEBHOOK_URL"),
    alert_email_recipients: System.get_env("ALERT_EMAIL_RECIPIENTS"),
    alert_from_email: System.get_env("ALERT_FROM_EMAIL") || "alerts@pipeforge.com"

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :pipeforge, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pipeforge, PipeForgeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pipeforge, PipeForgeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pipeforge, PipeForgeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Configure ExAws for MinIO/S3 in production
  config :ex_aws,
    access_key_id: System.get_env("MINIO_ACCESS_KEY"),
    secret_access_key: System.get_env("MINIO_SECRET_KEY"),
    region: System.get_env("MINIO_REGION") || "us-east-1"

  s3_endpoint = System.get_env("MINIO_ENDPOINT") || raise "MINIO_ENDPOINT environment variable is required"

  config :ex_aws, :s3,
    scheme: "https://",
    host: s3_endpoint,
    port: 443

  config :pipeforge, :storage,
    bucket: System.get_env("MINIO_BUCKET") || "pipeforge-uploads",
    region: System.get_env("MINIO_REGION") || "us-east-1"
end
