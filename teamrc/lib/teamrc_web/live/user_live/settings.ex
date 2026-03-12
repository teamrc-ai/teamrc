defmodule TeamrcWeb.UserLive.Settings do
  use TeamrcWeb, :live_view

  alias Teamrc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_scope.user
    user_data = Accounts.get_user_with_machine_tokens(current_user.id)
    profile = user_data && Teamrc.Repo.preload(user_data, :user_profile) |> Map.get(:user_profile)

    {:ok,
     assign(socket,
       page_title: "Settings",
       current_user: current_user,
       current_tab: :account,
       user_data: user_data,
       display_name: (profile && profile.display_name) || "",
       display_name_dirty: false,
       email_form: to_form(%{"email" => current_user.email}),
       password_form: to_form(%{"current_password" => "", "password" => "", "password_confirmation" => ""}),
       confirming_delete: false,
       trigger_submit_email: false,
       trigger_submit_password: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "security" -> :security
        "privacy" -> :privacy
        _ -> :account
      end

    {:noreply, assign(socket, current_tab: tab)}
  end

  # --- Account tab events ---

  @impl true
  def handle_event("update_display_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, display_name: value, display_name_dirty: true)}
  end

  def handle_event("save_display_name", _params, socket) do
    display_name = String.trim(socket.assigns.display_name)

    case Accounts.update_display_name(socket.assigns.current_user, display_name) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(display_name_dirty: false)
         |> put_flash(:info, "Display name updated.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update display name.")}
    end
  end

  def handle_event("validate_email", %{"user" => params}, socket) do
    {:noreply, assign(socket, email_form: to_form(params, action: :validate))}
  end

  def handle_event("save_email", %{"user" => %{"email" => email}}, socket) do
    current_user = socket.assigns.current_user

    case Accounts.apply_user_email(current_user, %{email: email}) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          current_user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:noreply,
         socket
         |> put_flash(:info, "A confirmation link has been sent to your new email address.")}

      {:error, changeset} ->
        {:noreply, assign(socket, email_form: to_form(changeset, action: :validate))}
    end
  end

  # --- Security tab events ---

  def handle_event("validate_password", %{"user" => params}, socket) do
    {:noreply, assign(socket, password_form: to_form(params, action: :validate))}
  end

  def handle_event("save_password", %{"user" => params}, socket) do
    current_user = socket.assigns.current_user

    case Accounts.update_user_password(current_user, %{
           password: params["password"],
           password_confirmation: params["password_confirmation"]
         }) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated successfully.")
         |> assign(
           password_form:
             to_form(%{"current_password" => "", "password" => "", "password_confirmation" => ""})
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :validate))}
    end
  end

  # --- Privacy tab events ---

  def handle_event("export_data", _params, socket) do
    case Accounts.export_user_data(socket.assigns.current_user.id) do
      {:ok, data} ->
        json = Jason.encode!(data, pretty: true)
        {:noreply, push_event(socket, "trc:download", %{data: json, filename: "teamrc-export.json"})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to export data.")}
    end
  end

  def handle_event("confirm_delete_account", _params, socket) do
    {:noreply, assign(socket, confirming_delete: true)}
  end

  def handle_event("cancel_delete_account", _params, socket) do
    {:noreply, assign(socket, confirming_delete: false)}
  end

  def handle_event("delete_account", _params, socket) do
    case Accounts.delete_user_and_data(socket.assigns.current_user) do
      :ok ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete account. Please try again.")}
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">Settings</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Manage your account, security, and data.
        </p>
      </div>

      <%!-- Tab navigation --%>
      <nav class="flex gap-1 border-b border-base-300 pb-0">
        <.tab_link label="Account" tab={:account} current={@current_tab} />
        <.tab_link label="Security" tab={:security} current={@current_tab} />
        <.tab_link label="Data & Privacy" tab={:privacy} current={@current_tab} />
      </nav>

      <%!-- Tab content --%>
      <div :if={@current_tab == :account}>
        <.account_tab
          current_user={@current_user}
          display_name={@display_name}
          display_name_dirty={@display_name_dirty}
          email_form={@email_form}
        />
      </div>

      <div :if={@current_tab == :security}>
        <.security_tab
          current_user={@current_user}
          password_form={@password_form}
        />
      </div>

      <div :if={@current_tab == :privacy}>
        <.privacy_tab
          current_user={@current_user}
          confirming_delete={@confirming_delete}
        />
      </div>
    </div>
    """
  end

  # --- Tab link component ---

  defp tab_link(assigns) do
    ~H"""
    <.link
      patch={~p"/users/settings" <> if(@tab == :account, do: "", else: "?tab=#{@tab}")}
      class={[
        "trc-focus rounded-t-md px-3 py-2 text-xs font-medium transition-colors -mb-px border-b-2",
        if(@current == @tab,
          do: "border-primary text-primary",
          else: "border-transparent text-base-content/50 hover:text-base-content/70 hover:border-base-300"
        )
      ]}
    >
      <%= @label %>
    </.link>
    """
  end

  # --- Account tab ---

  defp account_tab(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Display name --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Display Name
        </h2>
        <p class="text-xs text-base-content/50 mb-3">
          Used in team participant lists instead of your email address.
        </p>
        <div class="flex items-end gap-3">
          <div class="flex-1">
            <label for="display-name" class="sr-only">Display name</label>
            <input
              id="display-name"
              type="text"
              value={@display_name}
              phx-keyup="update_display_name"
              phx-debounce="300"
              placeholder="Enter a display name"
              maxlength="64"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm font-mono placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>
          <button
            :if={@display_name_dirty}
            phx-click="save_display_name"
            class="trc-focus rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
          >
            Save
          </button>
        </div>
      </section>

      <%!-- Email --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Email Address
        </h2>
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-mono"><%= @current_user.email %></p>
              <p class="text-xs text-base-content/50 mt-0.5">
                <%= if @current_user.confirmed_at do %>
                  Verified
                <% else %>
                  Unverified
                <% end %>
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Connected accounts --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Connected Accounts
        </h2>
        <p class="text-xs text-base-content/50 mb-3">
          OAuth providers linked to your account for sign-in.
        </p>
        <div class="space-y-2">
          <.oauth_provider_row
            provider="GitHub"
            connected={@current_user.provider == "github"}
            icon="github"
          />
          <.oauth_provider_row
            provider="Google"
            connected={@current_user.provider == "google"}
            icon="google"
          />
        </div>
      </section>
    </div>
    """
  end

  # --- Security tab ---

  defp security_tab(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Change password --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Change Password
        </h2>
        <p class="text-xs text-base-content/50 mb-4">
          Update your password. You will need to enter your current password to confirm.
        </p>
        <form phx-submit="save_password" phx-change="validate_password" class="space-y-4 max-w-sm">
          <div>
            <label for="current-password" class="block text-xs font-medium text-base-content/70 mb-1">
              Current password
            </label>
            <input
              id="current-password"
              name="user[current_password]"
              type="password"
              value={@password_form.params["current_password"]}
              autocomplete="current-password"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>
          <div>
            <label for="new-password" class="block text-xs font-medium text-base-content/70 mb-1">
              New password
            </label>
            <input
              id="new-password"
              name="user[password]"
              type="password"
              value={@password_form.params["password"]}
              autocomplete="new-password"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>
          <div>
            <label for="confirm-password" class="block text-xs font-medium text-base-content/70 mb-1">
              Confirm new password
            </label>
            <input
              id="confirm-password"
              name="user[password_confirmation]"
              type="password"
              value={@password_form.params["password_confirmation"]}
              autocomplete="new-password"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>
          <button
            type="submit"
            class="trc-focus rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
          >
            Update password
          </button>
        </form>
      </section>

      <%!-- Two-factor auth placeholder --%>
      <section class="border-t border-base-300/60 pt-6">
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Two-Factor Authentication
        </h2>
        <div class="rounded-lg border border-base-300 border-dashed bg-base-200/20 px-4 py-6 text-center">
          <p class="text-sm text-base-content/50">
            Two-factor authentication will be available in a future release.
          </p>
        </div>
      </section>
    </div>
    """
  end

  # --- Privacy tab ---

  defp privacy_tab(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Export data --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Export Data
        </h2>
        <p class="text-xs text-base-content/50 mb-3">
          Download a JSON file containing all your account data, teams, and machine associations.
        </p>
        <button
          phx-click="export_data"
          class="trc-focus inline-flex items-center gap-1.5 rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-medium text-base-content/70 hover:text-base-content/80 hover:border-base-300/80 transition-colors"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" />
          </svg>
          Export my data
        </button>
      </section>

      <%!-- Terms acceptance history --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Terms of Service
        </h2>
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-base-content/70">Terms accepted</p>
              <p class="text-xs text-base-content/50 mt-0.5 font-mono">
                <%= if @current_user.accepted_terms_at do %>
                  <%= Calendar.strftime(@current_user.accepted_terms_at, "%B %d, %Y at %H:%M UTC") %>
                <% else %>
                  Not yet accepted
                <% end %>
              </p>
            </div>
            <a
              href={~p"/terms"}
              class="text-xs text-primary hover:text-primary/80 transition-colors"
            >
              View terms
            </a>
          </div>
        </div>
      </section>

      <%!-- Delete account --%>
      <section class="border-t border-base-300/60 pt-6">
        <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Delete Account
        </h2>
        <p class="text-xs text-base-content/50 mb-3">
          Permanently delete your account and all associated data. This action cannot be undone.
          Teams you created will remain accessible to other members.
        </p>

        <%= if @confirming_delete do %>
          <div role="alert" class="rounded-lg border border-error/30 bg-error/5 p-4 space-y-3">
            <p class="text-sm text-error font-medium">Are you sure you want to delete your account?</p>
            <p class="text-xs text-base-content/60">
              This will remove your machines, team associations, and all personal data.
            </p>
            <div class="flex items-center gap-2">
              <button
                phx-click="delete_account"
                class="trc-focus rounded-md px-3 py-1.5 text-xs font-medium bg-error text-error-content hover:brightness-110 transition-colors"
              >
                Yes, delete everything
              </button>
              <button
                phx-click="cancel_delete_account"
                class="trc-focus rounded-md px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        <% else %>
          <button
            phx-click="confirm_delete_account"
            class="trc-focus inline-flex items-center gap-1.5 rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-error hover:border-error/30 hover:bg-error/5 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
            </svg>
            Delete account
          </button>
        <% end %>
      </section>
    </div>
    """
  end

  # --- OAuth provider row component ---

  attr :provider, :string, required: true
  attr :connected, :boolean, required: true
  attr :icon, :string, required: true

  defp oauth_provider_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border border-base-300 bg-base-100 px-4 py-3">
      <div class="flex items-center gap-3">
        <div class="flex h-8 w-8 items-center justify-center rounded-md bg-base-200">
          <.oauth_icon name={@icon} />
        </div>
        <div>
          <p class="text-sm font-medium"><%= @provider %></p>
          <p class="text-xs text-base-content/50">
            <%= if @connected, do: "Connected", else: "Not connected" %>
          </p>
        </div>
      </div>
      <div>
        <%= if @connected do %>
          <span class="inline-flex items-center gap-1 rounded-md bg-success/10 px-2 py-1 text-xs font-medium text-success">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
            </svg>
            Linked
          </span>
        <% else %>
          <a
            href={"/auth/#{String.downcase(@provider)}"}
            class="trc-focus rounded-md border border-base-300 px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/80 hover:border-base-300/80 transition-colors"
          >
            Connect
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  defp oauth_icon(%{name: "github"} = assigns) do
    ~H"""
    <svg class="h-4 w-4 text-base-content/70" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
    </svg>
    """
  end

  defp oauth_icon(%{name: "google"} = assigns) do
    ~H"""
    <svg class="h-4 w-4" viewBox="0 0 24 24">
      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
      <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
    </svg>
    """
  end

  defp oauth_icon(assigns) do
    ~H"""
    <div class="h-4 w-4 rounded-full bg-base-content/20"></div>
    """
  end
end
