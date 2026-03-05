defmodule TeambridgeWeb.Router do
  use TeambridgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TeambridgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeambridgeWeb do
    pipe_through :browser

    live "/", TeamLive, :index
  end

  scope "/api", TeambridgeWeb do
    pipe_through :api

    post "/teams", ApiController, :create_team
    get "/teams/:token", ApiController, :get_team
    post "/sync", ApiController, :sync
    post "/push", ApiController, :push
    post "/pull", ApiController, :pull
  end
end
