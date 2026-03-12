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
          fun.()

        invite ->
          if DateTime.compare(invite.expires_at, DateTime.utc_now()) == :gt do
            fun.()
          else
            {:noreply,
             socket
             |> assign(invite_access: nil, can_edit: false, invite_code: nil)
             |> put_flash(:error, "This invite has expired. Changes cannot be saved.")}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit this team.")}
    end
  end
end
