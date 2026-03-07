defmodule TeamrcWeb.DashboardLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if is_nil(socket.assigns[:clerk_user_id]) do
      {:ok, redirect(socket, to: ~p"/new")}
    else
      {:ok, load_dashboard(socket)}
    end
  end

  defp load_dashboard(socket) do
    account = Accounts.get_account_with_tokens(socket.assigns.clerk_user_id)

    if account do
      teams = Accounts.get_account_teams(account.id)
      team_ids = Enum.map(teams, & &1.id)
      participants = Accounts.resolve_participants_batch(team_ids)

      active_machines =
        account.account_tokens
        |> Enum.reject(& &1.revoked_at)
        |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime})

      assign(socket,
        page_title: "Dashboard",
        account: account,
        machines: active_machines,
        teams: teams,
        participants: participants,
        confirming_revoke: nil
      )
    else
      assign(socket,
        page_title: "Dashboard",
        account: nil,
        machines: [],
        teams: [],
        participants: %{},
        confirming_revoke: nil
      )
    end
  end

  @impl true
  def handle_event("confirm_revoke", %{"token" => token}, socket) do
    {:noreply, assign(socket, confirming_revoke: token)}
  end

  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, confirming_revoke: nil)}
  end

  def handle_event("revoke_machine", %{"token" => token}, socket) do
    account = socket.assigns.account

    case Accounts.revoke_token(account.id, token) do
      :ok ->
        socket =
          socket
          |> assign(confirming_revoke: nil)
          |> load_dashboard()
          |> put_flash(:info, "Machine revoked successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke machine.")}
    end
  end

  # --- Helpers ---

  defp time_ago(nil), do: "never"

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hr ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp truncate_token(token) when is_binary(token) do
    String.slice(token, 0, 12) <> "..."
  end

  defp truncate_token(_), do: ""

  defp participant_display(participants, my_email) do
    Enum.map(participants, fn
      p when p == my_email -> "you"
      "anonymous" -> "anonymous"
      email -> email
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-sm text-base-content/50 mt-1">
            Manage your machines and teams.
          </p>
        </div>
        <a
          href={~p"/new"}
          class="trc-focus inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
          </svg>
          Create team
        </a>
      </div>

      <%!-- Machines Section --%>
      <section>
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Your Machines</h2>
          <span class="text-xs text-base-content/25 font-mono"><%= length(@machines) %></span>
        </div>

        <div :if={@machines == []} class="rounded-lg border border-base-300 border-dashed bg-base-200/20 p-8 text-center">
          <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-base-200 mb-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/30" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
            </svg>
          </div>
          <p class="text-sm text-base-content/50 mb-1">No machines linked yet</p>
          <p class="text-xs text-base-content/30">
            Run <code class="font-mono bg-base-200 rounded px-1.5 py-0.5">teamrc login</code> in your terminal to link a machine.
          </p>
        </div>

        <div :if={@machines != []} class="space-y-2">
          <div
            :for={machine <- @machines}
            class="group flex items-center gap-4 rounded-lg border border-base-300 bg-base-100 px-4 py-3 transition-colors hover:border-base-300/80"
          >
            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/40">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate">
                  <%= machine.machine_name || "Unnamed machine" %>
                </span>
                <code class="text-xs font-mono text-base-content/30 hidden sm:inline">
                  <%= truncate_token(machine.token) %>
                </code>
              </div>
              <div class="text-xs text-base-content/40 mt-0.5">
                Last seen <%= time_ago(machine.last_seen_at) %>
              </div>
            </div>

            <%!-- Revoke confirmation --%>
            <div :if={@confirming_revoke == machine.token} class="flex items-center gap-2 animate-[fadeIn_150ms_ease-out]">
              <span class="text-xs text-error/70">Revoke access?</span>
              <button
                phx-click="revoke_machine"
                phx-value-token={machine.token}
                class="trc-focus rounded px-2 py-1 text-xs font-medium bg-error/10 text-error hover:bg-error/20 transition-colors"
              >
                Confirm
              </button>
              <button
                phx-click="cancel_revoke"
                class="trc-focus rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors"
              >
                Cancel
              </button>
            </div>

            <button
              :if={@confirming_revoke != machine.token}
              phx-click="confirm_revoke"
              phx-value-token={machine.token}
              class="trc-focus rounded px-2 py-1 text-xs font-medium text-base-content/25 hover:text-error hover:bg-error/5 transition-colors sm:opacity-0 sm:group-hover:opacity-100"
            >
              Revoke
            </button>
          </div>
        </div>
      </section>

      <%!-- Teams Section --%>
      <section>
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Your Teams</h2>
          <span class="text-xs text-base-content/25 font-mono"><%= length(@teams) %></span>
        </div>

        <div :if={@teams == []} class="rounded-lg border border-base-300 border-dashed bg-base-200/20 p-8 text-center">
          <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-base-200 mb-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/30" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
            </svg>
          </div>
          <p class="text-sm text-base-content/50 mb-1">No teams yet</p>
          <p class="text-xs text-base-content/30">
            <a href={~p"/new"} class="text-primary hover:text-primary/80">Create a team</a> to get started, or join one with
            <code class="font-mono bg-base-200 rounded px-1.5 py-0.5">teamrc join &lt;invite&gt;</code>
          </p>
        </div>

        <div :if={@teams != []} class="space-y-2">
          <div
            :for={team <- @teams}
            class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 transition-colors hover:border-base-300/80"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="text-sm font-semibold font-mono"><%= team.name %></span>
                <div class="flex items-center gap-2 text-xs text-base-content/30">
                  <span class="font-mono"><%= length(team.members) %> agents</span>
                  <span :if={team.rules && team.rules != []} class="font-mono">
                    &middot; <%= length(team.rules) %> rules
                  </span>
                </div>
              </div>
            </div>
            <div :if={Map.get(@participants, team.id)} class="mt-1.5 flex flex-wrap gap-1">
              <span
                :for={p <- participant_display(Map.get(@participants, team.id, []), @clerk_email)}
                class={[
                  "inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono",
                  if(p == "you",
                    do: "bg-primary/10 text-primary",
                    else: "bg-base-200/60 text-base-content/40"
                  )
                ]}
              >
                <%= p %>
              </span>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
