defmodule Teamrc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Validate required config in production
    validate_prod_config!()

    # Start :inets and :ssl once at boot (needed for JWKS fetching via :httpc)
    :inets.start()
    :ssl.start()

    # Create ETS table for JWKS caching before endpoint starts
    if :ets.whereis(:clerk_jwks_cache) == :undefined do
      :ets.new(:clerk_jwks_cache, [:named_table, :set, :public, read_concurrency: true])
    end

    children = [
      TeamrcWeb.Telemetry,
      Teamrc.Repo,
      {DNSCluster, query: Application.get_env(:relay, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Teamrc.PubSub},
      {Teamrc.Teams, name: Teamrc.Teams},
      {Teamrc.DeviceAuth, name: Teamrc.DeviceAuth},
      # Start to serve requests, typically the last entry
      TeamrcWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Teamrc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TeamrcWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp validate_prod_config! do
    if Application.get_env(:teamrc, :env, :dev) == :prod do
      config = Application.get_env(:teamrc, Teamrc.ClerkJWT, [])

      unless Keyword.get(config, :issuer) do
        raise "CLERK_ISSUER must be set in production"
      end

      unless Keyword.get(config, :jwks_url) do
        raise "CLERK_JWKS_URL must be set in production"
      end
    end
  end
end
