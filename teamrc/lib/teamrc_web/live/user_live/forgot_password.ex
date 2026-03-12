defmodule TeamrcWeb.UserLive.ForgotPassword do
  @moduledoc """
  Password reset request page. Collects the user's email and sends a reset link.
  """
  use TeamrcWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: "user")

    {:ok,
     assign(socket,
       page_title: "Reset password",
       form: form
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <%!-- Header --%>
      <div class="text-center mb-8">
        <div class="flex justify-center mb-4">
          <img src={~p"/images/logo.svg"} width="32" height="32" alt="teamrc" />
        </div>
        <h1 class="text-xl font-bold tracking-tight">Reset your password</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Enter your email and we'll send you a reset link.
        </p>
      </div>

      <%!-- Card --%>
      <div class="rounded-lg border border-base-300 bg-base-100 p-6">
        <.form
          for={@form}
          id="reset_password_form"
          action={~p"/users/forgot-password"}
          phx-change="validate"
          class="space-y-4"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            placeholder="you@example.com"
            required
            class="w-full input input-sm"
          />

          <button
            type="submit"
            phx-disable-with="Sending..."
            class="trc-focus w-full rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Send reset link
          </button>
        </.form>
      </div>

      <%!-- Footer links --%>
      <p class="mt-6 text-center text-xs text-base-content/50">
        Remember your password?
        <a href={~p"/users/log-in"} class="font-medium text-primary/80 hover:text-primary transition-colors">
          Log in
        </a>
      </p>
    </div>
    """
  end
end
