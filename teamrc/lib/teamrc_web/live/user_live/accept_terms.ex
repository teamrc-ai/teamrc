defmodule TeamrcWeb.UserLive.AcceptTerms do
  @moduledoc """
  LiveView for accepting Terms of Service after OAuth sign-in.

  Users who sign in via OAuth but have not yet accepted terms are redirected here.
  After accepting, they are routed through a controller action that creates
  the session and redirects to the dashboard.
  """

  use TeamrcWeb, :live_view

  alias Teamrc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md mt-16">
      <h1 class="text-2xl font-bold mb-4">Accept Terms of Service</h1>
      <p class="mb-4 text-zinc-600">
        Please review and accept our
        <.link navigate={~p"/terms"} class="text-indigo-600 underline">Terms of Service</.link>
        and
        <.link navigate={~p"/privacy"} class="text-indigo-600 underline">Privacy Policy</.link>
        to continue.
      </p>
      <form phx-submit="accept">
        <label class="flex items-start gap-2 mb-4">
          <input type="checkbox" name="accepted" value="true" required class="mt-1" />
          <span class="text-sm">I agree to the Terms of Service and Privacy Policy</span>
        </label>
        <button type="submit" class="w-full rounded bg-indigo-600 px-4 py-2 text-white hover:bg-indigo-700">
          Continue
        </button>
      </form>
    </div>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    pending_user_id = session["pending_oauth_user_id"]

    {:ok,
     socket
     |> assign(:pending_user_id, pending_user_id)}
  end

  @impl true
  def handle_event("accept", %{"accepted" => "true"}, socket) do
    current_scope = socket.assigns[:current_scope]
    current_user = current_scope && current_scope.user

    case socket.assigns.pending_user_id do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      user_id ->
        # Security: require authenticated user AND cross-check against pending_user_id
        if is_nil(current_user) || current_user.id != user_id do
          {:noreply,
           socket
           |> put_flash(:error, "Session mismatch. Please log in again.")
           |> redirect(to: ~p"/users/log-in")}
        else
          user = Accounts.get_user!(user_id)
          {:ok, _user} = Accounts.accept_terms(user, "2026-03-11")

          # Redirect through controller to renew session (LiveView can't set cookies)
          {:noreply,
           socket
           |> put_flash(:info, "Terms accepted. Welcome!")
           |> redirect(to: ~p"/users/complete-login")}
        end
    end
  end

  @impl true
  def handle_event("accept", _params, socket) do
    {:noreply, socket}
  end
end
