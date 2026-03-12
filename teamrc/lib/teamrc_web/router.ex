defmodule TeamrcWeb.Router do
  use TeamrcWeb, :router

  import TeamrcWeb.UserAuth
  import Phoenix.LiveDashboard.Router

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

    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.ApiVersion
    plug TeamrcWeb.Plugs.VerifySignature
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  pipeline :public_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.ApiVersion
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  # Session-based API auth for account endpoints
  pipeline :session_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug :fetch_session
    plug :fetch_current_scope_for_user
    plug :require_authenticated_user
    plug TeamrcWeb.Plugs.VerifyOrigin
    plug TeamrcWeb.Plugs.PIIHeader
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  # Session + signature API auth for sensitive endpoints
  pipeline :session_and_signature_api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug :fetch_session
    plug :fetch_current_scope_for_user
    plug :require_authenticated_user
    plug TeamrcWeb.Plugs.VerifyOrigin
    plug TeamrcWeb.Plugs.PIIHeader
    plug TeamrcWeb.Plugs.VerifySignature
    plug TeamrcWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
  end

  # Stricter rate limiting for auth endpoints (Bcrypt is CPU-expensive)
  pipeline :auth_rate_limit do
    plug TeamrcWeb.Plugs.RateLimiter, limit: 10, window_ms: 60_000, unauth_ip_limit: 10
  end

  # Store redirect_to query param in session for post-login return (used by OAuth)
  pipeline :store_redirect do
    plug :persist_redirect_to
  end

  # Health check — no auth, no SSL redirect, no pipelines
  scope "/", TeamrcWeb do
    get "/health", PageController, :health
  end

  scope "/auth", TeamrcWeb do
    pipe_through [:browser, :store_redirect]

    get "/github", OAuthController, :request
    get "/github/callback", OAuthController, :callback
    get "/google", OAuthController, :request
    get "/google/callback", OAuthController, :callback
  end

  scope "/", TeamrcWeb do
    pipe_through :browser

    get "/", PageController, :index

    live_session :public,
      layout: {TeamrcWeb.Layouts, :app},
      on_mount: [{TeamrcWeb.UserAuth, :mount_current_scope}] do
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
  end

  # Authenticated LiveView routes — Plug handles initial HTTP redirect + return-to
  # storage, LiveView on_mount handles websocket reconnection
  scope "/", TeamrcWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      layout: {TeamrcWeb.Layouts, :app},
      on_mount: [{TeamrcWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive
    end
  end

  # Live dashboard — open in dev, admin-only in prod
  scope "/admin" do
    pipe_through :browser

    live_dashboard "/dashboard",
      metrics: TeamrcWeb.Telemetry,
      on_mount: [{TeamrcWeb.AdminAuth, :admin}]
  end

  if Application.compile_env(:teamrc, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## ──────────────────────────────────────────────────────────
  ## phx.gen.auth routes
  ## ──────────────────────────────────────────────────────────

  scope "/", TeamrcWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TeamrcWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", TeamrcWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TeamrcWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/users/forgot-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :new
      live "/users/accept-terms", UserLive.AcceptTerms, :new
    end

    delete "/users/log-out", UserSessionController, :delete
  end

  # Auth actions with stricter rate limiting (Bcrypt is CPU-expensive)
  scope "/", TeamrcWeb do
    pipe_through [:browser, :auth_rate_limit, :store_redirect]

    post "/users/register", UserSessionController, :register
    post "/users/log-in", UserSessionController, :create
    post "/users/complete-login", UserSessionController, :terms_accepted
    post "/users/forgot-password", UserSessionController, :forgot_password
    post "/users/reset-password/:token", UserSessionController, :reset_password
  end

  # Store redirect_to query param in session for post-login return
  defp persist_redirect_to(conn, _opts) do
    case conn.params["redirect_to"] do
      path when is_binary(path) and byte_size(path) > 0 ->
        if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
          Plug.Conn.put_session(conn, :user_return_to, path)
        else
          conn
        end

      _ ->
        conn
    end
  end

  ## ──────────────────────────────────────────────────────────
  ## API routes
  ## ──────────────────────────────────────────────────────────

  # Public API (no auth required)
  scope "/api", TeamrcWeb do
    pipe_through :public_api

    get "/teams/clone/:clone_token", ApiController, :clone_team
  end

  # CLI API (ed25519 signature auth)
  scope "/api", TeamrcWeb do
    pipe_through :api

    post "/auth/device", AuthController, :create_device
    get "/auth/device/:device_code", AuthController, :poll_device

    post "/join", ApiController, :join_team
    post "/teams", ApiController, :create_team
    post "/teams/preview", ApiController, :preview_team
    post "/teams/invite", ApiController, :create_invite
    post "/teams/visibility", ApiController, :set_visibility
    post "/teams/claim", ApiController, :claim_ownership
    delete "/token/:token/erase", ApiController, :erase_token
    get "/teams/all/:token", ApiController, :get_teams
    get "/teams/:token/head", ApiController, :head_team
    get "/teams/:token", ApiController, :get_team
  end

  # Account API (session-based auth)
  scope "/api", TeamrcWeb do
    pipe_through :session_api

    get "/account", AccountController, :show
    get "/account/teams", AccountController, :teams
    get "/account/export", AccountController, :export
    delete "/account/machines/:token", AccountController, :revoke_machine
    delete "/account", AccountController, :delete
  end

  # Account API with additional signature verification
  scope "/api", TeamrcWeb do
    pipe_through :session_and_signature_api

    post "/account/reassociate", AccountController, :reassociate
  end
end
