import Config

config :teamrc, Teamrc.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 5432,
  database: "teamrc_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teamrc, TeamrcWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bibB0UGWxn38tb8APHsRyiAEBP/9FraMluESsmoCqudqRwduisFuPc1E+RH5OBQb",
  server: false

# Skip signature verification in tests by default.
# Security-specific tests override this to test the auth plug directly.
# E2E tests set SKIP_AUTH=false to enable real signature verification.
config :teamrc, :skip_auth, System.get_env("SKIP_AUTH") != "false"

# Reduce bcrypt rounds for faster tests
config :bcrypt_elixir, log_rounds: 1

# Swoosh test adapter (no actual sending)
config :teamrc, Teamrc.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
