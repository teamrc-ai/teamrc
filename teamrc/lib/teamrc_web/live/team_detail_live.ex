defmodule TeamrcWeb.TeamDetailLive do
  use TeamrcWeb, :live_view

  alias Teamrc.{Accounts, Teams}
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, TokenTeam, AccountToken}
  import Ecto.Query

  @impl true
  def mount(%{"id" => team_id}, _session, socket) do
    case load_team(team_id, socket.assigns) do
      {:ok, data} ->
        {:ok,
         assign(socket,
           page_title: data.team.name,
           team: data.team,
           machines: data.machines,
           participants: data.participants,
           invites: data.invites,
           can_edit: data.can_edit,
           editing: nil,
           edit_team_name: data.team.name,
           new_member_name: "",
           new_member_role: "",
           generating_invite: false,
           generated_invite: nil
         )}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Team not found.")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  defp load_team(team_id, assigns) do
    team =
      Team
      |> where(id: ^team_id)
      |> preload(:members)
      |> Repo.one()

    case team do
      nil ->
        :not_found

      team ->
        clerk_user_id = assigns[:clerk_user_id]

        # Get machines associated with this team
        machines = load_team_machines(team.id)

        # Check if current user has access
        can_edit = if clerk_user_id do
          account = Accounts.get_account_with_tokens(clerk_user_id)
          if account do
            tokens = Enum.map(account.account_tokens, & &1.token)
            Enum.any?(machines, fn m -> m.token in tokens end)
          else
            false
          end
        else
          false
        end

        participants = Accounts.resolve_participants(team.id)

        # Get active invites
        invites = load_active_invites(team.id)

        {:ok, %{
          team: team,
          machines: machines,
          participants: participants,
          invites: invites,
          can_edit: can_edit
        }}
    end
  end

  defp load_team_machines(team_id) do
    from(tt in TokenTeam,
      left_join: at in AccountToken,
      on: at.token == tt.token and is_nil(at.revoked_at),
      where: tt.team_id == ^team_id,
      select: %{
        token: tt.token,
        scope: tt.scope,
        project_name: tt.project_name,
        last_seen_at: coalesce(tt.last_seen_at, at.last_seen_at),
        machine_name: at.machine_name
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.token)
  end

  defp load_active_invites(team_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(i in Teamrc.Schema.Invite,
      where: i.team_id == ^team_id and i.expires_at > ^now,
      order_by: [desc: :inserted_at],
      select: %{code: i.code, expires_at: i.expires_at}
    )
    |> Repo.all()
  end

  @impl true
  def handle_event("toggle_edit", %{"section" => section}, socket) do
    editing = if socket.assigns.editing == section, do: nil, else: section
    {:noreply, assign(socket, editing: editing)}
  end

  def handle_event("update_edit_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, edit_team_name: value)}
  end

  def handle_event("save_team_name", _params, socket) do
    team = socket.assigns.team
    new_name = String.trim(socket.assigns.edit_team_name)

    if new_name != "" and new_name != team.name do
      case team
           |> Team.changeset(%{name: new_name})
           |> Repo.update() do
        {:ok, updated_team} ->
          {:noreply,
           socket
           |> assign(team: Repo.preload(updated_team, :members, force: true), editing: nil, page_title: new_name)
           |> put_flash(:info, "Team renamed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to rename team.")}
      end
    else
      {:noreply, assign(socket, editing: nil)}
    end
  end

  def handle_event("update_new_member_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, new_member_name: value)}
  end

  def handle_event("update_new_member_role", %{"value" => value}, socket) do
    {:noreply, assign(socket, new_member_role: value)}
  end

  def handle_event("add_member", _params, socket) do
    name = String.trim(socket.assigns.new_member_name)
    role = String.trim(socket.assigns.new_member_role)
    team = socket.assigns.team

    if name != "" and role != "" do
      case %Teamrc.Schema.Member{team_id: team.id}
           |> Teamrc.Schema.Member.changeset(%{name: name, role: role})
           |> Repo.insert() do
        {:ok, _member} ->
          updated_team = Repo.preload(team, :members, force: true)
          {:noreply,
           socket
           |> assign(team: updated_team, new_member_name: "", new_member_role: "")
           |> put_flash(:info, "Member added.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to add member.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"member-id" => member_id}, socket) do
    team = socket.assigns.team

    case Repo.get(Teamrc.Schema.Member, member_id) do
      nil ->
        {:noreply, socket}

      member when member.team_id == team.id ->
        Repo.delete(member)
        updated_team = Repo.preload(team, :members, force: true)
        {:noreply,
         socket
         |> assign(team: updated_team)
         |> put_flash(:info, "Member removed.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("generate_invite", _params, socket) do
    team = socket.assigns.team

    # Find a token for this team to use for invite generation
    case find_user_token_for_team(socket.assigns, team.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unable to generate invite. No linked machine found for this team.")}

      token ->
        case Teams.create_invite(token, 24, team.id) do
          {:ok, code, expires_at} ->
            invites = load_active_invites(team.id)
            {:noreply,
             socket
             |> assign(invites: invites, generated_invite: %{code: code, expires_at: expires_at})}

          :error ->
            {:noreply, put_flash(socket, :error, "Failed to generate invite.")}
        end
    end
  end

  def handle_event("dismiss_generated_invite", _params, socket) do
    {:noreply, assign(socket, generated_invite: nil)}
  end

  defp find_user_token_for_team(assigns, team_id) do
    clerk_user_id = assigns[:clerk_user_id]
    if is_nil(clerk_user_id), do: nil, else: do_find_token(clerk_user_id, team_id)
  end

  defp do_find_token(clerk_user_id, team_id) do
    account = Accounts.get_account_with_tokens(clerk_user_id)
    if account do
      tokens = Enum.map(account.account_tokens, & &1.token)
      from(tt in TokenTeam,
        where: tt.team_id == ^team_id and tt.token in ^tokens,
        select: tt.token,
        limit: 1
      )
      |> Repo.one()
    else
      nil
    end
  end

  # --- Helpers ---

  defp truncate_token(token) when is_binary(token) do
    String.slice(token, 0, 12) <> "..."
  end
  defp truncate_token(_), do: ""

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

  defp invite_time_remaining(expires_at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(expires_at, now, :second)

    cond do
      diff <= 0 -> "expired"
      diff < 3600 -> "#{div(diff, 60)} min"
      diff < 86400 -> "#{div(diff, 3600)} hr"
      true -> "#{div(diff, 86400)} days"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Back link --%>
      <a
        href={~p"/dashboard"}
        class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-base-content/40 hover:text-base-content/70 transition-colors rounded px-1 -ml-1"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
          <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
        </svg>
        Dashboard
      </a>

      <%!-- Team header --%>
      <div class="flex items-center justify-between">
        <div>
          <div :if={@editing != "name"} class="flex items-center gap-3">
            <h1 class="text-2xl font-bold tracking-tight font-mono"><%= @team.name %></h1>
            <button
              :if={@can_edit}
              phx-click="toggle_edit"
              phx-value-section="name"
              class="trc-focus rounded p-1 text-base-content/20 hover:text-base-content/50 transition-colors"
              aria-label="Rename team"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </button>
          </div>
          <div :if={@editing == "name"} class="flex items-center gap-2">
            <input
              type="text"
              value={@edit_team_name}
              phx-keyup="update_edit_team_name"
              class="trc-focus rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-lg font-mono font-bold focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
            <button
              phx-click="save_team_name"
              class="trc-focus rounded-md bg-primary px-3 py-1.5 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
            >
              Save
            </button>
            <button
              phx-click="toggle_edit"
              phx-value-section="name"
              class="trc-focus rounded-md px-3 py-1.5 text-sm font-medium text-base-content/40 hover:text-base-content/60 transition-colors"
            >
              Cancel
            </button>
          </div>
          <p class="text-sm text-base-content/40 mt-1 font-mono"><%= @team.id %></p>
        </div>
      </div>

      <%!-- Platforms --%>
      <div :if={@team.platforms != []}>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">Platforms</p>
        <div class="flex flex-wrap gap-1.5">
          <span
            :for={platform <- @team.platforms}
            class="inline-flex items-center rounded-md bg-primary/5 border border-primary/10 px-2.5 py-1 text-xs font-mono text-primary/70"
          >
            <%= platform %>
          </span>
        </div>
      </div>

      <%!-- Members --%>
      <section>
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Members
            <span class="font-mono text-base-content/30 ml-1"><%= length(@team.members) %></span>
          </p>
          <button
            :if={@can_edit && @editing != "members"}
            phx-click="toggle_edit"
            phx-value-section="members"
            class="trc-focus text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            Edit
          </button>
          <button
            :if={@can_edit && @editing == "members"}
            phx-click="toggle_edit"
            phx-value-section="members"
            class="trc-focus text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors"
          >
            Done
          </button>
        </div>

        <div class="space-y-1.5">
          <div
            :for={member <- @team.members}
            class="group flex items-center gap-3 rounded-md border border-base-300 bg-base-100 px-3 py-2.5"
          >
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-mono font-medium"><%= member.name %></span>
              </div>
              <p class="text-xs text-base-content/50 mt-0.5"><%= member.role %></p>
              <div :if={member.rules != []} class="flex flex-wrap gap-1 mt-1.5">
                <span
                  :for={rule_id <- member.rules}
                  class="inline-flex items-center rounded bg-base-200/60 px-1.5 py-0.5 text-[10px] font-mono text-base-content/40"
                >
                  <%= rule_id %>
                </span>
              </div>
            </div>
            <button
              :if={@editing == "members"}
              phx-click="remove_member"
              phx-value-member-id={member.id}
              class="trc-focus rounded p-1 text-base-content/20 hover:bg-error/10 hover:text-error transition-colors"
              aria-label="Remove member"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Add member form (edit mode) --%>
        <div :if={@editing == "members"} class="mt-3 rounded-md border border-dashed border-base-300 bg-base-200/20 p-3 space-y-2">
          <div class="flex gap-2">
            <input
              type="text"
              value={@new_member_name}
              phx-keyup="update_new_member_name"
              placeholder="agent-name"
              class="trc-focus flex-1 rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
            <input
              type="text"
              value={@new_member_role}
              phx-keyup="update_new_member_role"
              placeholder="Role description"
              class="trc-focus flex-[2] rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>
          <button
            phx-click="add_member"
            disabled={@new_member_name == "" || @new_member_role == ""}
            class={[
              "trc-focus rounded px-3 py-1.5 text-xs font-semibold transition-all",
              if(@new_member_name == "" || @new_member_role == "",
                do: "bg-base-300 text-base-content/30 cursor-not-allowed",
                else: "bg-primary text-primary-content hover:brightness-110"
              )
            ]}
          >
            Add member
          </button>
        </div>
      </section>

      <%!-- Rules --%>
      <section :if={@team.rules != []}>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">
          Rules
          <span class="font-mono text-base-content/30 ml-1"><%= length(@team.rules) %></span>
        </p>
        <div class="space-y-1.5">
          <div
            :for={rule <- @team.rules}
            class="rounded-md border border-base-300 bg-base-100 px-3 py-2.5"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-mono font-medium text-primary/70"><%= rule["id"] %></span>
            </div>
            <p class="text-sm text-base-content/60 line-clamp-2"><%= rule["body"] %></p>
          </div>
        </div>
      </section>

      <%!-- Skills --%>
      <section :if={@team.skills != []}>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">
          Skills
          <span class="font-mono text-base-content/30 ml-1"><%= length(@team.skills) %></span>
        </p>
        <div class="space-y-1.5">
          <div
            :for={skill <- @team.skills}
            class="rounded-md border border-base-300 bg-base-100 px-3 py-2.5"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-mono font-medium text-primary/70"><%= skill["id"] %></span>
              <span :if={skill["description"]} class="text-xs text-base-content/40"><%= skill["description"] %></span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Active machines --%>
      <section>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">
          Active Machines
          <span class="font-mono text-base-content/30 ml-1"><%= length(@machines) %></span>
        </p>

        <div :if={@machines == []} class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
          <p class="text-xs text-base-content/40">No machines syncing this team.</p>
        </div>

        <div :if={@machines != []} class="space-y-1.5">
          <div
            :for={machine <- @machines}
            class="flex items-center gap-3 rounded-md border border-base-300 bg-base-100 px-3 py-2.5"
          >
            <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-base-200 text-base-content/30">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate"><%= machine.machine_name || "Unnamed" %></span>
                <code class="text-[10px] font-mono text-base-content/25"><%= truncate_token(machine.token) %></code>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/35 mt-0.5">
                <span :if={machine.scope == "global"} class="font-mono">global</span>
                <span :if={machine.project_name} class="font-mono"><%= machine.project_name %></span>
                <span><%= time_ago(machine.last_seen_at) %></span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Participants --%>
      <section :if={@participants != []}>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">Participants</p>
        <div class="flex flex-wrap gap-1.5">
          <span
            :for={p <- @participants}
            class={[
              "inline-flex items-center rounded px-2 py-1 text-xs font-mono",
              if(p == @clerk_email,
                do: "bg-primary/10 text-primary",
                else: "bg-base-200/60 text-base-content/40"
              )
            ]}
          >
            <%= if p == @clerk_email, do: "you (#{p})", else: p %>
          </span>
        </div>
      </section>

      <%!-- Invites --%>
      <section>
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Invites
            <span class="font-mono text-base-content/30 ml-1"><%= length(@invites) %></span>
          </p>
          <button
            :if={@can_edit}
            phx-click="generate_invite"
            class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
            </svg>
            Generate invite
          </button>
        </div>

        <%!-- Newly generated invite --%>
        <div :if={@generated_invite} class="rounded-lg border border-primary/30 bg-primary/5 p-4 mb-4 animate-[fadeIn_150ms_ease-out]">
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-medium text-primary">New invite generated</p>
            <button
              phx-click="dismiss_generated_invite"
              class="trc-focus text-xs text-base-content/30 hover:text-base-content/50 transition-colors"
            >
              Dismiss
            </button>
          </div>
          <div class="terminal-block rounded-md overflow-hidden">
            <div class="flex items-center justify-between px-3 py-2">
              <code class="text-emerald-400 text-sm font-mono">npx teamrc join <%= @generated_invite.code %></code>
              <button
                phx-click={JS.dispatch("trc:copy", detail: %{text: "npx teamrc join #{@generated_invite.code}"})}
                class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
              >
                copy
              </button>
            </div>
          </div>
          <p class="text-xs text-base-content/40 mt-2">
            Expires in <%= invite_time_remaining(@generated_invite.expires_at) %>
          </p>
        </div>

        <%!-- Existing invites --%>
        <div :if={@invites != []} class="space-y-1.5">
          <div
            :for={invite <- @invites}
            class="flex items-center justify-between rounded-md border border-base-300 bg-base-100 px-3 py-2"
          >
            <code class="text-xs font-mono text-base-content/50"><%= invite.code %></code>
            <span class="text-[10px] text-base-content/30">
              expires in <%= invite_time_remaining(invite.expires_at) %>
            </span>
          </div>
        </div>

        <div :if={@invites == [] && is_nil(@generated_invite)} class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
          <p class="text-xs text-base-content/40">No active invites.</p>
        </div>
      </section>
    </div>
    """
  end
end
