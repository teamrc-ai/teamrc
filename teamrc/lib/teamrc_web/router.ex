defmodule TeamrcWeb.Router do
  use TeamrcWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TeamrcWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug TeamrcWeb.Plugs.CORS
    plug TeamrcWeb.Plugs.VerifySignature
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

    live "/", TeamLive, :index
    live "/auth/verify", AuthVerifyLive
  end

  scope "/api", TeamrcWeb do
    pipe_through :api

    post "/auth/device", AuthController, :create_device
    get "/auth/device/:device_code", AuthController, :poll_device

    post "/join", ApiController, :join_team
    post "/teams", ApiController, :create_team
    get "/teams/:token", ApiController, :get_team
    post "/sync", ApiController, :sync
    get "/sync/check", ApiController, :sync_check
    post "/push", ApiController, :push
    get "/pull", ApiController, :pull
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
