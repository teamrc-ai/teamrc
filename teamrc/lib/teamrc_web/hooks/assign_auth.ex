defmodule TeamrcWeb.Hooks.AssignAuth do
  @moduledoc """
  LiveView on_mount hook that assigns Clerk auth state to the socket.
  Makes :clerk_user_id and :clerk_email available to all LiveViews
  and their layouts.
  """

  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:clerk_user_id, session["clerk_user_id"])
     |> assign(:clerk_email, session["clerk_email"])}
  end
end
