import Config

config :teambridge, Teambridge.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 5432,
  database: "teambridge_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teambridge, TeambridgeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+cZpAXhe1a8s8TG+clf1HmR4LftN+piWOf3bdYjJachkey2+7mWoU3/p/ksLXPQo",
  server: false

# Skip signature verification in tests by default.
# Security-specific tests override this to test the auth plug directly.
config :teambridge, :skip_auth, true

# Skip Clerk JWT verification in tests by default.
# The VerifyClerkJWT test overrides this to test the plug directly.
config :teambridge, :skip_clerk_auth, true

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
