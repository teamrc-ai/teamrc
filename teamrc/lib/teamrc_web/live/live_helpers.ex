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
      case socket.assigns[:invite_access] do
        nil ->
          # Re-validate participant status against the database to catch
          # revocations that occurred after mount (stale can_edit fix)
          current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
          team = socket.assigns[:team]

          if team && Teamrc.Accounts.is_team_participant?(current_user && current_user.id, team.id) do
            fun.()
          else
            {:noreply,
             socket
             |> assign(can_edit: false)
             |> put_flash(:error, "You are no longer a participant in this team.")}
          end

        _invite ->
          # Re-validate invite against the database to catch revocations
          case Teamrc.Teams.get_valid_invite(socket.assigns.team.id, socket.assigns[:invite_code]) do
            nil ->
              {:noreply,
               socket
               |> assign(invite_access: nil, can_edit: false, invite_code: nil)
               |> put_flash(:error, "This invite has expired or been revoked. Changes cannot be saved.")}

            _valid_invite ->
              fun.()
          end
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit this team.")}
    end
  end
end
