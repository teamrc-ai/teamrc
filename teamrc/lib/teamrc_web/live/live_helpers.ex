defmodule TeamrcWeb.LiveHelpers do
  @moduledoc "Shared helpers for LiveView modules."

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  @doc """
  Guard that checks `can_edit` and validates invite expiry before executing `fun`.
  Returns a `{:noreply, socket}` tuple suitable for use in handle_event callbacks.
  """
  def require_edit_access(socket, fun) do
    if socket.assigns.can_edit do
      # Re-validate access against the database to catch
      # revocations that occurred after mount (stale session fix).
      current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
      team = socket.assigns[:team]

      # Re-verify creator sessions against DB each time (claim_secret may
      # have been cleared by an ownership claim since mount).
      is_creator_valid =
        if socket.assigns[:is_creator_session] do
          creator_sessions = socket.assigns[:creator_sessions] || %{}
          creator_token = Map.get(creator_sessions, team && team.id)
          is_binary(creator_token) && Teamrc.Teams.verify_creator_token(team.id, creator_token)
        else
          false
        end

      has_access =
        is_creator_valid ||
          (team && Teamrc.Accounts.is_team_participant?(current_user && current_user.id, team.id))

      if has_access do
        fun.()
      else
        {:noreply,
         socket
         |> assign(can_edit: false, is_creator_session: false)
         |> put_flash(:error, "You are no longer a participant in this team.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit this team.")}
    end
  end
end
