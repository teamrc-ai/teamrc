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
#     PHX_SERVER=true bin/teamrc start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :teamrc, TeamrcWeb.Endpoint, server: true
end

config :teamrc, TeamrcWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000")), ip: {0, 0, 0, 0}]

config :teamrc, env: config_env()

# Clerk frontend publishable key (optional — enables Sign In button on web UI)
if clerk_pk = System.get_env("CLERK_PUBLISHABLE_KEY") do
  config :teamrc, :clerk_publishable_key, clerk_pk
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :teamrc, Teamrc.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: System.get_env("DATABASE_SSL", "true") != "false"

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

  config :teamrc, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  session_signing_salt =
    System.get_env("SESSION_SIGNING_SALT") ||
      raise "environment variable SESSION_SIGNING_SALT is missing."

  live_view_signing_salt =
    System.get_env("LIVE_VIEW_SIGNING_SALT") ||
      raise "environment variable LIVE_VIEW_SIGNING_SALT is missing."

  session_encryption_salt =
    System.get_env("SESSION_ENCRYPTION_SALT") ||
      raise "environment variable SESSION_ENCRYPTION_SALT is missing."

  config :teamrc, TeamrcWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base,
    session_options: [signing_salt: session_signing_salt, encryption_salt: session_encryption_salt],
    live_view: [signing_salt: live_view_signing_salt]

  # Clerk JWT verification (optional — enables account linking + dashboard)
  clerk_jwks_url = System.get_env("CLERK_JWKS_URL")
  clerk_issuer = System.get_env("CLERK_ISSUER")
  clerk_audience = System.get_env("CLERK_AUDIENCE")

  if clerk_jwks_url && clerk_issuer do
    config :teamrc, Teamrc.ClerkJWT,
      jwks_url: clerk_jwks_url,
      issuer: clerk_issuer,
      audience: clerk_audience
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :teamrc, TeamrcWeb.Endpoint,
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
  #     config :teamrc, TeamrcWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
