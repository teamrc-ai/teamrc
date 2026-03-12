defmodule Teamrc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:teamrc, :repo])

    # Eagerly populate the template catalog ETS cache
    Teamrc.Catalog.reload()

    children = [
      TeamrcWeb.Telemetry,
      Teamrc.Repo,
      {DNSCluster, query: Application.get_env(:teamrc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Teamrc.PubSub},

      {Finch, name: Swoosh.Finch},
      TeamrcWeb.Plugs.RateLimiter.Server,
      Teamrc.DeviceAuth.CleanupTask,
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
end
