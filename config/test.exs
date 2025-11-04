import Config

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

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
