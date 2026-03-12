defmodule TeamrcWeb.AuthVerifyLive do
  use TeamrcWeb, :live_view

  alias Teamrc.DeviceAuth
  alias Teamrc.Accounts

  @impl true
  def mount(params, _session, socket) do
    code = Map.get(params, "code", "")
    current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       page_title: "Verify Device",
       current_user: current_user,
       step: determine_initial_step(current_user, code),
       user_code: code,
       error: nil
     )}
  end

  defp determine_initial_step(current_user, code) do
    cond do
      is_nil(current_user) -> :sign_in_required
      code != "" && valid_code_format?(code) -> :consent
      true -> :enter_code
    end
  end

  @impl true
  def handle_event("update_code", %{"value" => raw}, socket) do
    formatted = format_code(raw)
    {:noreply, assign(socket, user_code: formatted, error: nil)}
  end

  def handle_event("submit_code", _params, socket) do
    code = String.trim(socket.assigns.user_code)

    if valid_code_format?(code) do
      {:noreply, assign(socket, step: :consent, error: nil)}
    else
      {:noreply, assign(socket, error: "Please enter a valid 8-character code (XXXX-XXXX).")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, step: :enter_code, error: nil)}
  end

  def handle_event("confirm", _params, socket) do
    code = socket.assigns.user_code
    current_user = socket.assigns.current_user

    cond do
      is_nil(current_user) ->
        {:noreply, assign(socket, step: :sign_in_required, error: nil)}

      is_nil(current_user.accepted_terms_at) ->
        {:noreply,
         socket
         |> put_flash(:error, "You must accept the Terms of Service before linking a device.")
         |> assign(error: "Please accept the Terms of Service first.")}

      true ->
        case DeviceAuth.confirm_request(code, current_user.id, current_user.email) do
          {:ok, confirmed_req} ->
            case Accounts.link_machine_token(current_user.id, confirmed_req.token, nil) do
              {:ok, _at} ->
                {:noreply, assign(socket, step: :success, error: nil)}

              _ ->
                {:noreply, assign(socket, error: "Failed to link account. Please try again.")}
            end

          {:error, :not_found} ->
            DeviceAuth.record_failed_attempt(code)

            {:noreply,
             assign(socket,
               step: :enter_code,
               error: "This code has expired or is invalid. Please run `teamrc login` again."
             )}

          {:error, :already_confirmed} ->
            {:noreply,
             assign(socket,
               error: "This code has already been confirmed."
             )}

        end
    end
  end

  # --- Helpers ---

  defp format_code(raw) do
    clean =
      raw
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "")
      |> String.slice(0, 8)

    if String.length(clean) > 4 do
      String.slice(clean, 0, 4) <> "-" <> String.slice(clean, 4, 4)
    else
      clean
    end
  end

  defp valid_code_format?(code) do
    Regex.match?(~r/^[A-Z0-9]{4}-[A-Z0-9]{4}$/, code)
  end

  defp step_num(:sign_in_required), do: 0
  defp step_num(:enter_code), do: 1
  defp step_num(:consent), do: 2
  defp step_num(:success), do: 3

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto mt-4">
      <%!-- Step indicator --%>
      <div class="flex items-center gap-2 mb-10 text-xs font-medium">
        <.step_dot number={1} label="Sign In" active={step_num(@step) >= 1} current={@step == :sign_in_required} />
        <div class={"w-6 h-px " <> if(step_num(@step) >= 1, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_dot number={2} label="Enter Code" active={step_num(@step) >= 1} current={@step == :enter_code} />
        <div class={"w-6 h-px " <> if(step_num(@step) >= 2, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_dot number={3} label="Confirm" active={step_num(@step) >= 2} current={@step == :consent} />
        <div class={"w-6 h-px " <> if(step_num(@step) >= 3, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_dot number={4} label="Done" active={step_num(@step) >= 3} current={@step == :success} />
      </div>

      <%!-- Step 0: Sign in required --%>
      <div :if={@step == :sign_in_required}>
        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Sign in to continue</h1>
          <p class="text-sm text-base-content/60">
            You need to sign in with your account before linking a device.
          </p>
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200/30 p-6 mb-6 text-center">
          <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10 mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1 1 21.75 8.25Z" />
            </svg>
          </div>
          <p class="text-sm text-base-content/70 mb-4">
            Sign in with your account to link this device code:
          </p>
          <div :if={@user_code != ""} class="mb-4">
            <code class="text-lg font-mono tracking-[0.2em] text-primary font-semibold"><%= @user_code %></code>
          </div>
          <.link
            href={~p"/users/log-in?redirect_to=/auth/verify" <> if(@user_code != "", do: "&code=#{@user_code}", else: "")}
            class="trc-focus inline-block rounded-md bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Sign in
          </.link>
        </div>

        <p class="text-xs text-center text-base-content/50">
          After signing in, you'll return here to confirm the device link.
        </p>
      </div>

      <%!-- Step 1: Enter Code --%>
      <div :if={@step == :enter_code}>
        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Link your machine</h1>
          <p class="text-sm text-base-content/60">
            Enter the code shown in your terminal.
          </p>
        </div>

        <%!-- Signed in indicator --%>
        <div class="flex items-center gap-2 rounded-md bg-success/5 border border-success/20 px-3 py-2 mb-6">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
          <span class="text-xs text-base-content/70">
            Signed in as <span class="font-mono font-medium"><%= @current_user.email %></span>
          </span>
        </div>

        <form phx-submit="submit_code" class="space-y-6">
          <div>
            <label class="block text-xs font-medium text-base-content/70 uppercase tracking-wider mb-2" for="user-code">
              Device code
            </label>
            <input
              id="user-code"
              type="text"
              value={@user_code}
              phx-keyup="update_code"
              phx-mounted={Phoenix.LiveView.JS.focus()}
              placeholder="XXXX-XXXX"
              autocomplete="off"
              spellcheck="false"
              maxlength="9"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-4 py-3 text-center text-2xl font-mono tracking-[0.3em] placeholder:text-base-content/50 placeholder:tracking-[0.3em] focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>

          <div :if={@error} role="alert" class="rounded-md border border-error/30 bg-error/5 px-4 py-3">
            <p class="text-sm text-error"><%= @error %></p>
          </div>

          <button
            type="submit"
            disabled={not valid_code_format?(@user_code)}
            class={[
              "trc-focus w-full rounded-md px-4 py-2.5 text-sm font-semibold shadow-sm transition-all duration-150",
              if(valid_code_format?(@user_code),
                do: "bg-primary text-primary-content hover:brightness-110 active:scale-[0.99]",
                else: "bg-base-300 text-base-content/50 cursor-not-allowed"
              )
            ]}
          >
            Continue
          </button>
        </form>
      </div>

      <%!-- Step 2: Consent --%>
      <div :if={@step == :consent}>
        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Confirm device link</h1>
          <p class="text-sm text-base-content/60">
            Review the details below before linking this machine to your account.
          </p>
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200/30 p-5 mb-4 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">Account</span>
            <span class="text-sm font-mono text-base-content/70"><%= @current_user.email %></span>
          </div>
          <div class="border-t border-base-300/60"></div>
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">Device code</span>
            <span class="text-lg font-mono tracking-[0.2em] text-primary font-semibold"><%= @user_code %></span>
          </div>
        </div>

        <div class="rounded-lg border border-warning/30 bg-warning/5 p-4 mb-6">
          <div class="flex items-start gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-warning shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
            </svg>
            <div>
              <p class="text-sm font-medium text-warning">Security check</p>
              <p class="text-sm text-base-content/70 mt-1">
                Only confirm if you just ran <code class="font-mono text-xs bg-base-200 rounded px-1 py-0.5">teamrc login</code> and see this code in your terminal.
              </p>
            </div>
          </div>
        </div>

        <div :if={@error} role="alert" class="rounded-md border border-error/30 bg-error/5 px-4 py-3 mb-4">
          <p class="text-sm text-error"><%= @error %></p>
        </div>

        <div class="flex gap-3">
          <button
            phx-click="cancel"
            class="trc-focus flex-1 rounded-md border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content/70 hover:bg-base-200 transition-colors"
          >
            Cancel
          </button>
          <button
            phx-click="confirm"
            phx-disable-with="Linking..."
            class="trc-focus flex-1 rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Link this machine
          </button>
        </div>
      </div>

      <%!-- Step 3: Success --%>
      <div :if={@step == :success}>
        <div class="text-center py-8">
          <div class="flex items-center justify-center mb-6">
            <div class="flex h-14 w-14 items-center justify-center rounded-full bg-success/15">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-7 w-7 text-success" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
              </svg>
            </div>
          </div>
          <h1 class="text-2xl font-bold tracking-tight mb-2">Machine linked</h1>
          <p class="text-sm text-base-content/60 mb-6">
            You can close this tab and return to your terminal.
          </p>
          <a
            :if={@current_user}
            href={~p"/dashboard"}
            class="trc-focus inline-flex items-center gap-2 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
          >
            Go to dashboard
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
            </svg>
          </a>
        </div>
      </div>
    </div>
    """
  end

  # --- Step indicator component ---

  defp step_dot(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <div class={[
        "flex items-center justify-center h-5 w-5 rounded-full text-[10px] font-semibold transition-colors",
        if(@current, do: "bg-primary text-primary-content", else:
          if(@active && !@current, do: "bg-primary/15 text-primary", else: "bg-base-300 text-base-content/50")
        )
      ]}>
        <%= if @active && !@current do %>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
        <% else %>
          <%= @number %>
        <% end %>
      </div>
      <span class={[
        "text-xs transition-colors hidden sm:inline",
        if(@current, do: "text-base-content font-medium", else:
          if(@active, do: "text-base-content/60", else: "text-base-content/50")
        )
      ]}>
        <%= @label %>
      </span>
    </div>
    """
  end
end
