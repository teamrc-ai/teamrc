defmodule TeamrcWeb.UserLive.ResetPassword do
  @moduledoc """
  Password reset form page. The user arrives here from the email reset link
  and sets a new password. M1 FIX: Password minimum 12 characters.
  """
  use TeamrcWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    form =
      to_form(
        %{"password" => "", "password_confirmation" => ""},
        as: "user"
      )

    {:ok,
     assign(socket,
       page_title: "Set new password",
       form: form,
       token: params["token"],
       trigger_submit: false
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form, trigger_submit: true)}
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
        <h1 class="text-xl font-bold tracking-tight">Set new password</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Choose a new password for your account.
        </p>
      </div>

      <%!-- Card --%>
      <div class="rounded-lg border border-base-300 bg-base-100 p-6">
        <.form
          for={@form}
          id="reset_password_form"
          action={~p"/users/reset-password/#{@token}"}
          phx-change="validate"
          phx-submit="reset_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            placeholder="At least 12 characters"
            required
            class="w-full input input-sm"
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            placeholder="Repeat your new password"
            required
            class="w-full input input-sm"
          />

          <button
            type="submit"
            phx-disable-with="Resetting..."
            class="trc-focus w-full rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Reset password
          </button>
        </.form>
      </div>

      <%!-- Footer links --%>
      <div class="mt-6 flex justify-center gap-4 text-xs text-base-content/50">
        <a href={~p"/users/log-in"} class="font-medium text-primary/80 hover:text-primary transition-colors">
          Log in
        </a>
        <span class="text-base-content/30">|</span>
        <a href={~p"/users/register"} class="font-medium text-primary/80 hover:text-primary transition-colors">
          Register
        </a>
      </div>
    </div>
    """
  end
end
