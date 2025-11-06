import Config

# Configure the database for testing
config :pipeforge, PipeForge.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: System.get_env("POSTGRES_DB") || "pipeforge_test",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pipeforge, PipeForgeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "DrQ5+pF9KaxsUhfjZCT+qKU7Bq8Yhn6StTUke2aIemHn/X7CJmrB62qyVYOS4S8u",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure Oban for testing (disable cron, use in-memory queues)
config :pipeforge, Oban,
  engine: Oban.Engines.Basic,
  repo: PipeForge.Repo,
  queues: false,
  plugins: false

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
