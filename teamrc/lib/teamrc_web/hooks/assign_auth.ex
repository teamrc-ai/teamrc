defmodule TeamrcWeb.Hooks.AssignAuth do
  @moduledoc """
  LiveView on_mount hook that assigns Clerk auth state to the socket.

  Two modes:
  - `:default` — assigns auth state but does not enforce login (for public pages)
  - `:require_auth` — redirects to "/" if no authenticated session exists
  """

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:clerk_user_id, session["clerk_user_id"])
     |> assign(:clerk_email, session["clerk_email"])}
  end

  def on_mount(:require_auth, _params, session, socket) do
    socket =
      socket
      |> assign(:clerk_user_id, session["clerk_user_id"])
      |> assign(:clerk_email, session["clerk_email"])

    if session["clerk_user_id"] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end
end
