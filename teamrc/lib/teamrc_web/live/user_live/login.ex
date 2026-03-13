defmodule TeamrcWeb.UserLive.Login do
  @moduledoc """
  Login page with OAuth-first flow (GitHub + Google) and email/password fallback.
  """
  use TeamrcWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    redirect_to = sanitize_redirect(Map.get(params, "redirect_to"))

    {:ok,
     assign(socket,
       page_title: "Log in",
       form: form,
       check_errors: false,
       trigger_submit: false,
       redirect_to: redirect_to
     ), temporary_assigns: [form: form]}
  end

  defp sanitize_redirect(nil), do: nil
  defp sanitize_redirect(""), do: nil

  defp sanitize_redirect(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      nil
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("submit", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form, check_errors: true, trigger_submit: true)}
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
        <h1 class="text-xl font-bold tracking-tight">Log in to teamrc</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Welcome back. Sign in to manage your teams.
        </p>
      </div>

      <%!-- Auth card --%>
      <div class="rounded-lg border border-base-300 bg-base-100 p-6">
        <%!-- OAuth buttons --%>
        <div class="space-y-2.5">
          <a
            href={if @redirect_to, do: ~p"/auth/github?redirect_to=#{@redirect_to}", else: ~p"/auth/github"}
            class="trc-focus flex w-full items-center justify-center gap-2.5 rounded-md bg-base-content px-4 py-2.5 text-sm font-medium text-base-100 transition-colors hover:bg-base-content/90 active:scale-[0.99]"
          >
            <svg class="h-4.5 w-4.5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path fill-rule="evenodd" clip-rule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
            </svg>
            Continue with GitHub
          </a>
          <a
            href={if @redirect_to, do: ~p"/auth/google?redirect_to=#{@redirect_to}", else: ~p"/auth/google"}
            class="trc-focus flex w-full items-center justify-center gap-2.5 rounded-md border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-medium text-base-content transition-colors hover:bg-base-200/60 active:scale-[0.99]"
          >
            <svg class="h-4.5 w-4.5" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
              <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
              <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
              <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
            </svg>
            Continue with Google
          </a>
        </div>

        <%!-- Divider --%>
        <div class="relative my-6">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-base-300"></div>
          </div>
          <div class="relative flex justify-center text-xs">
            <span class="bg-base-100 px-3 text-base-content/50">or</span>
          </div>
        </div>

        <%!-- Inline flash messages --%>
        <div :if={Phoenix.Flash.get(@flash, :info)} class="rounded-md border border-info/30 bg-info/5 px-4 py-3 mb-4">
          <p class="text-sm text-info">{Phoenix.Flash.get(@flash, :info)}</p>
        </div>
        <div :if={Phoenix.Flash.get(@flash, :error)} class="rounded-md border border-error/30 bg-error/5 px-4 py-3 mb-4">
          <p class="text-sm text-error">{Phoenix.Flash.get(@flash, :error)}</p>
        </div>

        <%!-- Email/password form --%>
        <.form
          for={@form}
          id="login_form"
          action={if @redirect_to, do: ~p"/users/log-in?redirect_to=#{@redirect_to}", else: ~p"/users/log-in"}
          phx-change="validate"
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
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
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            placeholder="Your password"
            required
            class="w-full input input-sm"
          />

          <div class="flex items-center justify-between">
            <.input
              field={@form[:remember_me]}
              type="checkbox"
              label="Remember me"
              class="checkbox checkbox-xs"
            />
            <a
              href={~p"/users/forgot-password"}
              class="text-xs font-medium text-primary/80 hover:text-primary transition-colors"
            >
              Forgot password?
            </a>
          </div>

          <button
            type="submit"
            phx-disable-with="Logging in..."
            class="trc-focus w-full rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Log in
          </button>
        </.form>

      </div>

      <%!-- Footer link --%>
      <p class="mt-6 text-center text-xs text-base-content/50">
        Don't have an account?
        <a href={if @redirect_to, do: ~p"/users/register?redirect_to=#{@redirect_to}", else: ~p"/users/register"} class="font-medium text-primary/80 hover:text-primary transition-colors">
          Register
        </a>
      </p>
    </div>
    """
  end
end
