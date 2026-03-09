defmodule TeamrcWeb.Router do
  use TeamrcWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TeamrcWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss:; font-src 'self' data:; frame-ancestors 'none'"
    }

    plug TeamrcWeb.Plugs.SessionClerkAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.VerifySignature
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  pipeline :public_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  pipeline :clerk_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.VerifyClerkJWT
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  pipeline :clerk_and_signature_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.VerifyClerkJWT
    plug TeamrcWeb.Plugs.VerifySignature
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  scope "/", TeamrcWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/auth/sign-out", PageController, :sign_out

    live_session :public,
      layout: {TeamrcWeb.Layouts, :app},
      on_mount: [{TeamrcWeb.Hooks.AssignAuth, :default}] do
      live "/new", TeamLive, :index
      live "/invite/:code", InviteLive
      live "/teams/:id", TeamDetailLive
      live "/teams/:team_id/members/:member_id", MemberDetailLive
      live "/guide/get-started", GuideLive, :get_started
      live "/guide", GuideLive, :overview
      live "/guide/concepts", GuideLive, :concepts
      live "/guide/cli", GuideLive, :cli
      live "/guide/platforms", GuideLive, :platforms
      live "/guide/sync", GuideLive, :sync
      live "/guide/config", GuideLive, :config
      live "/guide/web-ui", GuideLive, :web_ui
      live "/guide/faq", GuideLive, :faq
      live "/auth/verify", AuthVerifyLive
      live "/terms", LegalLive, :terms
      live "/privacy", LegalLive, :privacy
    end

    live_session :authenticated,
      layout: {TeamrcWeb.Layouts, :app},
      on_mount: [{TeamrcWeb.Hooks.AssignAuth, :require_auth}] do
      live "/dashboard", DashboardLive
    end
  end

  # Public API (no auth required)
  scope "/api", TeamrcWeb do
    pipe_through :public_api

    get "/teams/clone/:clone_token", ApiController, :clone_team
  end

  scope "/api", TeamrcWeb do
    pipe_through :api

    post "/auth/device", AuthController, :create_device
    get "/auth/device/:device_code", AuthController, :poll_device

    post "/join", ApiController, :join_team
    post "/teams", ApiController, :create_team
    post "/teams/preview", ApiController, :preview_team
    post "/teams/invite", ApiController, :create_invite
    get "/teams/all/:token", ApiController, :get_teams
    get "/teams/:token", ApiController, :get_team
  end

  scope "/api", TeamrcWeb do
    pipe_through :clerk_api

    get "/account", AccountController, :show
    get "/account/teams", AccountController, :teams
    delete "/account/machines/:token", AccountController, :revoke_machine
  end

  scope "/api", TeamrcWeb do
    pipe_through :clerk_and_signature_api

    post "/account/reassociate", AccountController, :reassociate
  end
end
