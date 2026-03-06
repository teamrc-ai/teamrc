defmodule TeambridgeWeb.AuthVerifyLive do
  use TeambridgeWeb, :live_view

  alias Teambridge.DeviceAuth
  alias Teambridge.Accounts

  @impl true
  def mount(params, session, socket) do
    code = Map.get(params, "code", "")

    {:ok,
     assign(socket,
       page_title: "Verify Device",
       step: :enter_code,
       user_code: code,
       error: nil,
       clerk_user_id: session["clerk_user_id"],
       clerk_email: session["clerk_email"]
     )}
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
    clerk_user_id = socket.assigns.clerk_user_id
    clerk_email = socket.assigns.clerk_email

    if is_nil(clerk_user_id) or is_nil(clerk_email) do
      {:noreply, assign(socket, error: "You must be signed in to link a device. Please sign in first.")}
    else
      case DeviceAuth.confirm_request(code, clerk_user_id, clerk_email) do
        :ok ->
          # Find or create the account and link the token
          with {:ok, account} <- Accounts.find_or_create_account(clerk_user_id, clerk_email),
               # Get the machine token from the device request to create the account_token link
               {:ok, request} <- DeviceAuth.get_request_by_user_code(code),
               {:ok, _at} <- Accounts.link_token(account.id, request.token, nil) do
            {:noreply, assign(socket, step: :success, error: nil)}
          else
            _ ->
              {:noreply, assign(socket, error: "Failed to link account. Please try again.")}
          end

      {:error, :not_found} ->
        # Could be expired or invalid
        {:noreply,
         assign(socket,
           step: :enter_code,
           error: "This code has expired or is invalid. Please run `teambridge login` again."
         )}

      {:error, :code_invalidated} ->
        {:noreply,
         assign(socket,
           step: :enter_code,
           error: "Too many failed attempts. Please run `teambridge login` again.",
           user_code: ""
         )}
      end
    end
  end

  # --- Helpers ---

  defp format_code(raw) do
    # Strip everything except alphanumeric, uppercase it
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto mt-8">
      <%!-- Step indicator --%>
      <div class="flex items-center gap-2 mb-10 text-xs font-medium">
        <.step_dot number={1} label="Enter Code" active={step_num(@step) >= 1} current={@step == :enter_code} />
        <div class={"w-8 h-px " <> if(step_num(@step) >= 2, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_dot number={2} label="Confirm" active={step_num(@step) >= 2} current={@step == :consent} />
        <div class={"w-8 h-px " <> if(step_num(@step) >= 3, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_dot number={3} label="Done" active={step_num(@step) >= 3} current={@step == :success} />
      </div>

      <%!-- Step 1: Enter Code --%>
      <div :if={@step == :enter_code}>
        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Link your machine</h1>
          <p class="text-sm text-base-content/50">
            Enter the code shown in your terminal.
          </p>
        </div>

        <form phx-submit="submit_code" class="space-y-6">
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-2" for="user-code">
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
              class="tb-focus w-full rounded-md border border-base-300 bg-base-100 px-4 py-3 text-center text-2xl font-mono tracking-[0.3em] placeholder:text-base-content/20 placeholder:tracking-[0.3em] focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>

          <div :if={@error} class="rounded-md border border-error/30 bg-error/5 px-4 py-3">
            <p class="text-sm text-error"><%= @error %></p>
          </div>

          <button
            type="submit"
            disabled={not valid_code_format?(@user_code)}
            class={[
              "tb-focus w-full rounded-md px-4 py-2.5 text-sm font-semibold shadow-sm transition-all duration-150",
              if(valid_code_format?(@user_code),
                do: "bg-primary text-primary-content hover:brightness-110 active:scale-[0.99]",
                else: "bg-base-300 text-base-content/30 cursor-not-allowed"
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
          <p class="text-sm text-base-content/50">
            Review the details below before linking this machine to your account.
          </p>
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200/30 p-5 mb-6">
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            Device code
          </p>
          <p class="text-2xl font-mono tracking-[0.3em] text-center text-primary font-semibold">
            <%= @user_code %>
          </p>
        </div>

        <div class="rounded-lg border border-warning/30 bg-warning/5 p-4 mb-8">
          <div class="flex items-start gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-warning shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
            </svg>
            <div>
              <p class="text-sm font-medium text-warning">Security check</p>
              <p class="text-sm text-base-content/60 mt-1">
                Only confirm if you just ran <code class="font-mono text-xs bg-base-200 rounded px-1 py-0.5">teambridge login</code> and see this code in your terminal.
              </p>
            </div>
          </div>
        </div>

        <div :if={@error} class="rounded-md border border-error/30 bg-error/5 px-4 py-3 mb-4">
          <p class="text-sm text-error"><%= @error %></p>
        </div>

        <div class="flex gap-3">
          <button
            phx-click="cancel"
            class="tb-focus flex-1 rounded-md border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content/60 hover:bg-base-200 transition-colors"
          >
            Cancel
          </button>
          <button
            phx-click="confirm"
            phx-disable-with="Linking..."
            class="tb-focus flex-1 rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
          >
            Confirm
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
          <h1 class="text-2xl font-bold tracking-tight mb-2">Machine linked successfully</h1>
          <p class="text-sm text-base-content/50">
            You can close this tab and return to your terminal.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # --- Step indicator component ---

  defp step_num(:enter_code), do: 1
  defp step_num(:consent), do: 2
  defp step_num(:success), do: 3

  defp step_dot(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <div class={[
        "flex items-center justify-center h-5 w-5 rounded-full text-[10px] font-semibold transition-colors",
        if(@current, do: "bg-primary text-primary-content", else:
          if(@active && !@current, do: "bg-primary/15 text-primary", else: "bg-base-300 text-base-content/30")
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
          if(@active, do: "text-base-content/50", else: "text-base-content/30")
        )
      ]}>
        <%= @label %>
      </span>
    </div>
    """
  end
end
