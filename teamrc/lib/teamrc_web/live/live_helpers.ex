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
      # revocations that occurred after mount (stale can_edit fix).
      # Creator sessions bypass the participant check since they
      # were verified at mount via bcrypt against the claim secret.
      current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
      team = socket.assigns[:team]
      is_creator_session = socket.assigns[:is_creator_session] == true

      has_access =
        is_creator_session ||
          (team && Teamrc.Accounts.is_team_participant?(current_user && current_user.id, team.id))

      if has_access do
        fun.()
      else
        {:noreply,
         socket
         |> assign(can_edit: false)
         |> put_flash(:error, "You are no longer a participant in this team.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit this team.")}
    end
  end
end
