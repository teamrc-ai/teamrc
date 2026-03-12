defmodule TeamrcWeb.DashboardLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_scope && socket.assigns.current_scope.user

    if is_nil(current_user) do
      {:ok, redirect(socket, to: ~p"/new")}
    else
      {:ok, load_dashboard(socket, current_user)}
    end
  end

  defp load_dashboard(socket, current_user) do
    user_data = Accounts.get_user_with_machine_tokens(current_user.id)

    if user_data do
      teams_with_machines = Accounts.get_user_teams_with_machines(current_user.id)
      team_ids = Enum.map(teams_with_machines, fn {team, _} -> team.id end)
      participants = Accounts.resolve_participants_batch(team_ids)

      hashed_participants =
        Map.new(participants, fn {team_id, emails} ->
          {team_id,
           Enum.map(emails, fn
             "anonymous" -> "anonymous"
             email -> Teamrc.PII.email_hash(email)
           end)}
        end)

      # Build enriched team data
      teams_data = Enum.map(teams_with_machines, fn {team, machines} ->
        %{
          id: team.id,
          name: team.name,
          members: team.members,
          skills: team.skills || [],
          platforms: team.platforms || [],
          machines: machines,
          participants: Map.get(hashed_participants, team.id, ["anonymous"])
        }
      end)

      active_machines =
        user_data.machine_tokens
        |> Enum.reject(& &1.revoked_at)
        |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime})

      # Build machine-to-teams lookup
      machine_teams = build_machine_teams(teams_with_machines, active_machines)

      assign(socket,
        page_title: "Dashboard",
        current_user: current_user,
        user_data: user_data,
        machines: active_machines,
        teams: teams_data,
        participants: hashed_participants,
        machine_teams: machine_teams,
        expanded_team: nil,
        confirming_revoke: nil,
        confirming_delete: false
      )
    else
      assign(socket,
        page_title: "Dashboard",
        current_user: current_user,
        user_data: nil,
        machines: [],
        teams: [],
        participants: %{},
        machine_teams: %{},
        expanded_team: nil,
        confirming_revoke: nil,
        confirming_delete: false
      )
    end
  end

  defp build_machine_teams(teams_with_machines, active_machines) do
    # For each machine token, find which teams it belongs to
    Enum.reduce(active_machines, %{}, fn machine, acc ->
      teams_for_machine =
        Enum.flat_map(teams_with_machines, fn {team, machines} ->
          case Enum.find(machines, fn m -> m.token == machine.token end) do
            nil -> []
            m -> [%{team_name: team.name, team_id: team.id, scope: m.scope, project_name: m.project_name}]
          end
        end)

      Map.put(acc, machine.token, teams_for_machine)
    end)
  end

  @impl true
  def handle_event("toggle_team", %{"team-id" => team_id}, socket) do
    expanded = if socket.assigns.expanded_team == team_id, do: nil, else: team_id
    {:noreply, assign(socket, expanded_team: expanded)}
  end

  def handle_event("confirm_revoke", %{"token" => token}, socket) do
    {:noreply, assign(socket, confirming_revoke: token)}
  end

  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, confirming_revoke: nil)}
  end

  def handle_event("revoke_machine", %{"token" => token}, socket) do
    current_user = socket.assigns.current_user

    case Accounts.revoke_machine_token(current_user.id, token) do
      :ok ->
        socket =
          socket
          |> assign(confirming_revoke: nil)
          |> load_dashboard(current_user)
          |> put_flash(:info, "Machine revoked successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke machine.")}
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

  def handle_event("export_data", _params, socket) do
    case Accounts.export_user_data(socket.assigns.current_user.id) do
      {:ok, data} ->
        json = Jason.encode!(data, pretty: true)
        {:noreply, push_event(socket, "trc:download", %{data: json, filename: "teamrc-export.json"})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to export data.")}
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

  defp participant_display(participants, my_email_hash) do
    Enum.map(participants, fn
      p when p == my_email_hash -> "you"
      "anonymous" -> "anonymous"
      hash -> String.slice(hash, 0, 8) <> "..."
    end)
  end

  defp platform_label(platforms) when is_list(platforms) and length(platforms) > 0 do
    Enum.join(platforms, ", ")
  end
  defp platform_label(_), do: nil

  defp machine_count(team) do
    length(team.machines)
  end

  defp most_recent_seen(machines) do
    machines
    |> Enum.map(fn m -> m.last_seen_at || m.tt_last_seen_at end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.max(dates, DateTime)
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :my_email_hash, Teamrc.PII.email_hash(assigns.current_user.email))

    ~H"""
    <div class="space-y-10">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Manage your machines and teams.
          </p>
        </div>
        <a
          href={~p"/new"}
          class="trc-focus inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-sm hover:brightness-110 active:scale-[0.99] transition-all duration-150"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
          </svg>
          Create team
        </a>
      </div>

      <%!-- Teams Section --%>
      <section>
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider">Your Teams</h2>
          <span class="text-xs text-base-content/50 font-mono"><%= length(@teams) %></span>
        </div>

        <div :if={@teams == []} class="rounded-lg border border-base-300 border-dashed bg-base-200/20 p-8 text-center">
          <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-base-200 mb-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/50" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
            </svg>
          </div>
          <p class="text-sm text-base-content/60 mb-1">No teams yet</p>
          <p class="text-xs text-base-content/50">
            <a href={~p"/new"} class="text-primary hover:text-primary/80">Create a team</a> to get started, or join one with
            <code class="font-mono bg-base-200 rounded px-1.5 py-0.5">teamrc join &lt;invite&gt;</code>
          </p>
        </div>

        <div :if={@teams != []} class="space-y-2">
          <div :for={team <- @teams}>
            <%!-- Team row (clickable to expand) --%>
            <button
              phx-click="toggle_team"
              phx-value-team-id={team.id}
              aria-expanded={@expanded_team == team.id}
              class="trc-focus w-full text-left rounded-lg border border-base-300 bg-base-100 px-4 py-3 transition-colors hover:border-base-300/80"
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3 min-w-0">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class={"h-3.5 w-3.5 text-base-content/50 transition-transform duration-150 shrink-0 #{if @expanded_team == team.id, do: "rotate-90", else: ""}"}
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
                  </svg>
                  <span class="text-sm font-semibold font-mono truncate"><%= team.name %></span>
                  <span class="text-xs text-base-content/50 font-mono shrink-0"><%= length(team.members) %> agents</span>
                </div>
                <div class="flex items-center gap-3 text-xs text-base-content/50 shrink-0 ml-4">
                  <span :if={platform_label(team.platforms)} class="hidden sm:inline font-mono">
                    <%= platform_label(team.platforms) %>
                  </span>
                  <span :if={machine_count(team) > 0} class="font-mono">
                    <%= machine_count(team) %> machine<%= if machine_count(team) != 1, do: "s" %>
                  </span>
                  <span :if={most_recent_seen(team.machines)} class="hidden sm:inline">
                    <%= time_ago(most_recent_seen(team.machines)) %>
                  </span>
                </div>
              </div>
            </button>

            <%!-- Expanded team detail --%>
            <div :if={@expanded_team == team.id} class="rounded-lg border border-base-300/60 bg-base-200/20 px-4 py-4 -mt-1 ml-4 space-y-4 animate-[fadeIn_150ms_ease-out]">
              <%!-- Members --%>
              <div>
                <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-2">Members</p>
                <div class="flex flex-wrap gap-1.5">
                  <div :for={member <- team.members} class="flex items-center gap-1.5 rounded bg-base-200/60 px-2 py-1">
                    <span class="text-xs font-mono text-base-content/70"><%= member.name %></span>
                    <span class="text-[10px] text-base-content/50"><%= member.role %></span>
                  </div>
                </div>
              </div>

              <%!-- Skills count --%>
              <div :if={length(team.skills) > 0} class="flex items-center gap-4">
                <span class="text-xs text-base-content/60 font-mono">
                  <%= length(team.skills) %> skill<%= if length(team.skills) != 1, do: "s" %>
                </span>
              </div>

              <%!-- Platforms --%>
              <div :if={team.platforms != []}>
                <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-2">Platforms</p>
                <div class="flex flex-wrap gap-1.5">
                  <span
                    :for={platform <- team.platforms}
                    class="inline-flex items-center rounded bg-primary/5 border border-primary/30 px-2 py-0.5 text-[11px] font-mono text-primary/80"
                  >
                    <%= platform %>
                  </span>
                </div>
              </div>

              <%!-- Participants --%>
              <div :if={Map.get(@participants, team.id)}>
                <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-2">Participants</p>
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={p <- participant_display(Map.get(@participants, team.id, []), @my_email_hash)}
                    class={[
                      "inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono",
                      if(p == "you",
                        do: "bg-primary/10 text-primary",
                        else: "bg-base-200/60 text-base-content/60"
                      )
                    ]}
                  >
                    <%= p %>
                  </span>
                </div>
              </div>

              <%!-- View detail link --%>
              <div class="pt-1">
                <a
                  href={~p"/teams/#{team.id}"}
                  class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  View team details
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
                  </svg>
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Machines Section --%>
      <section>
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider">Your Machines</h2>
          <span class="text-xs text-base-content/50 font-mono"><%= length(@machines) %></span>
        </div>

        <div :if={@machines == []} class="rounded-lg border border-base-300 border-dashed bg-base-200/20 p-8 text-center">
          <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-base-200 mb-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/50" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
            </svg>
          </div>
          <p class="text-sm text-base-content/60 mb-1">No machines linked yet</p>
          <p class="text-xs text-base-content/50">
            Run <code class="font-mono bg-base-200 rounded px-1.5 py-0.5">teamrc login</code> in your terminal to link a machine.
          </p>
        </div>

        <div :if={@machines != []} class="space-y-2">
          <div
            :for={machine <- @machines}
            class="group rounded-lg border border-base-300 bg-base-100 px-4 py-3 transition-colors hover:border-base-300/80"
          >
            <div class="flex items-center gap-4">
              <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/60">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
                </svg>
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium truncate">
                    <%= machine.machine_name || "Unnamed machine" %>
                  </span>
                  <code class="text-xs font-mono text-base-content/50 hidden sm:inline">
                    <%= truncate_token(machine.token) %>
                  </code>
                </div>
                <div class="text-xs text-base-content/60 mt-0.5">
                  Last seen <%= time_ago(machine.last_seen_at) %>
                </div>
              </div>

              <%!-- Revoke confirmation --%>
              <div :if={@confirming_revoke == machine.token} role="alert" class="flex items-center gap-2 animate-[fadeIn_150ms_ease-out]">
                <span class="text-xs text-error/70">Revoke access?</span>
                <button
                  phx-click="revoke_machine"
                  phx-value-token={machine.token}
                  class="trc-focus rounded px-3 py-2 text-xs font-medium bg-error/10 text-error hover:bg-error/20 transition-colors"
                >
                  Confirm
                </button>
                <button
                  phx-click="cancel_revoke"
                  class="trc-focus rounded px-3 py-2 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
                >
                  Cancel
                </button>
              </div>

              <button
                :if={@confirming_revoke != machine.token}
                phx-click="confirm_revoke"
                phx-value-token={machine.token}
                class="trc-focus rounded px-3 py-2 text-xs font-medium text-base-content/50 hover:text-error hover:bg-error/5 transition-colors sm:opacity-0 sm:group-hover:opacity-100 sm:focus:opacity-100"
              >
                Revoke
              </button>
            </div>

            <%!-- Machine team associations --%>
            <div :if={Map.get(@machine_teams, machine.token, []) != []} class="mt-2 ml-12 space-y-1">
              <div :for={mt <- Map.get(@machine_teams, machine.token, [])} class="flex items-center gap-2 text-xs text-base-content/60">
                <span :if={mt.scope == "global"} class="inline-flex items-center rounded bg-base-200/60 px-1.5 py-0.5 text-[10px] font-mono uppercase tracking-wider text-base-content/50">
                  global
                </span>
                <span :if={mt.scope == "project" && mt.project_name} class="font-mono text-base-content/50">
                  <%= mt.project_name %> &rarr;
                </span>
                <a href={~p"/teams/#{mt.team_id}"} class="font-mono text-primary/80 hover:text-primary transition-colors">
                  <%= mt.team_name %>
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Account section --%>
      <section class="border-t border-base-300/60 pt-8">
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xs font-medium text-base-content/60 uppercase tracking-wider">Account</h2>
        </div>

        <div class="space-y-3">
          <div class="flex items-center justify-between rounded-lg border border-base-300 bg-base-100 px-4 py-3">
            <div>
              <p class="text-sm font-medium"><%= @current_user.email %></p>
              <p class="text-xs text-base-content/60">Signed in</p>
            </div>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="trc-focus rounded px-2.5 py-1 text-xs font-medium text-base-content/60 hover:text-base-content/70 hover:bg-base-200/60 transition-colors"
            >
              Sign out
            </.link>
          </div>

          <div class="flex items-center gap-2">
            <button
              phx-click="export_data"
              class="trc-focus inline-flex items-center gap-1.5 rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-medium text-base-content/70 hover:text-base-content/80 hover:border-base-300/80 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" />
              </svg>
              Export my data
            </button>

            <%= if @confirming_delete do %>
              <div role="alert" class="flex items-center gap-2 animate-[fadeIn_150ms_ease-out]">
                <span class="text-xs text-error/70">Delete account and all data?</span>
                <button
                  phx-click="delete_account"
                  class="trc-focus rounded px-2.5 py-1 text-xs font-medium bg-error/10 text-error hover:bg-error/20 transition-colors"
                >
                  Yes, delete everything
                </button>
                <button
                  phx-click="cancel_delete_account"
                  class="trc-focus rounded px-3 py-2 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
                >
                  Cancel
                </button>
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
          </div>

          <p class="text-xs text-base-content/50">
            Deleting your account removes your machines and team associations. Teams you created will remain accessible to other members.
          </p>
        </div>
      </section>
    </div>
    """
  end
end
