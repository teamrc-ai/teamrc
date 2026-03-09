defmodule TeamrcWeb.TeamDetailLive do
  use TeamrcWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Teamrc.{Accounts, Catalog, Teams}
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, Invite, Member, TokenTeam, AccountToken}
  import Ecto.Query

  @max_members 20

  # --- Mount ---

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
           can_edit_owner: data.can_edit,
           can_edit: data.can_edit,
           invite_access: nil,
           invite_code: nil,
           editing_section: nil,
           edit_team_name: data.team.name,
           show_add_member: false,
           new_member_name: "",
           new_member_role: "",
           generating_invite: false,
           generated_invite: nil,
           skill_mode: nil,
           skill_catalog: nil,
           editing_skill: nil,
           skill_id: "",
           skill_title: "",
           skill_description: "",
           skill_body: "",
           skill_always_apply: false
         )}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Team not found.")
         |> redirect(to: ~p"/new")}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Check for invite code in query params (e.g. /teams/:id?invite=CODE)
    query = URI.parse(uri).query
    query_params = if query, do: URI.decode_query(query), else: %{}

    socket =
      case query_params["invite"] do
        nil ->
          socket

        invite_code ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)
          team = socket.assigns.team

          case Repo.one(
                 from(i in Invite,
                   where: i.code == ^invite_code and i.team_id == ^team.id and i.expires_at > ^now
                 )
               ) do
            nil ->
              socket

            invite ->
              assign(socket,
                invite_access: invite,
                invite_code: invite_code,
                can_edit: true
              )
          end
      end

    {:noreply, socket}
  end

  # --- Data loading ---

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
        machines = load_team_machines(team.id)

        can_edit =
          if clerk_user_id do
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
        invites = load_active_invites(team.id)

        {:ok,
         %{
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

    from(i in Invite,
      where: i.team_id == ^team_id and i.expires_at > ^now,
      order_by: [desc: :inserted_at],
      select: %{code: i.code, expires_at: i.expires_at}
    )
    |> Repo.all()
  end

  # --- Security ---

  defp require_edit_access(socket, fun) do
    cond do
      socket.assigns.can_edit_owner ->
        fun.()

      invite = socket.assigns[:invite_access] ->
        if DateTime.compare(invite.expires_at, DateTime.utc_now()) == :gt do
          fun.()
        else
          {:noreply,
           socket
           |> assign(invite_access: nil, can_edit: false, invite_code: nil)
           |> put_flash(:error, "This invite has expired. Changes cannot be saved.")}
        end

      true ->
        {:noreply, put_flash(socket, :error, "You don't have permission to edit this team.")}
    end
  end

  # --- Team name editing ---

  @impl true
  def handle_event("toggle_edit", %{"section" => section}, socket) do
    editing = if socket.assigns.editing_section == section, do: nil, else: section
    {:noreply, assign(socket, editing_section: editing)}
  end

  def handle_event("update_edit_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, edit_team_name: value)}
  end

  def handle_event("save_team_name", _params, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team
      new_name = String.trim(socket.assigns.edit_team_name)

      if new_name != "" and new_name != team.name do
        case team
             |> Team.changeset(%{name: new_name})
             |> Repo.update() do
          {:ok, updated_team} ->
            {:noreply,
             socket
             |> assign(
               team: Repo.preload(updated_team, :members, force: true),
               editing_section: nil,
               page_title: new_name
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to rename team.")}
        end
      else
        {:noreply, assign(socket, editing_section: nil)}
      end
    end)
  end

  # --- Member CRUD ---

  def handle_event("update_new_member_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, new_member_name: value)}
  end

  def handle_event("update_new_member_role", %{"value" => value}, socket) do
    {:noreply, assign(socket, new_member_role: value)}
  end

  def handle_event("toggle_add_member", _params, socket) do
    {:noreply, assign(socket, show_add_member: !socket.assigns.show_add_member)}
  end

  def handle_event("add_member", _params, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team

      if length(team.members) >= @max_members do
        {:noreply, put_flash(socket, :error, "Maximum #{@max_members} members reached.")}
      else
        name = String.trim(socket.assigns.new_member_name)
        role = String.trim(socket.assigns.new_member_role)

        if name != "" and role != "" do
          case %Member{team_id: team.id}
               |> Member.changeset(%{name: name, role: role})
               |> Repo.insert() do
            {:ok, _member} ->
              updated_team = Repo.preload(team, :members, force: true)

              {:noreply,
               assign(socket,
                 team: updated_team,
                 new_member_name: "",
                 new_member_role: "",
                 show_add_member: false
               )}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to add member.")}
          end
        else
          {:noreply, socket}
        end
      end
    end)
  end

  # --- Skill CRUD ---

  def handle_event("show_skill_picker", _params, socket) do
    existing_ids = MapSet.new(socket.assigns.team.skills, & &1["id"])

    catalog =
      Catalog.list_skill_categories()
      |> Enum.map(fn cat ->
        skills =
          cat["skills"]
          |> Enum.map(fn id -> Catalog.load_skill(id) end)
          |> Enum.reject(fn s -> MapSet.member?(existing_ids, s["id"]) end)

        %{id: cat["id"], label: cat["label"], skills: skills}
      end)
      |> Enum.reject(fn cat -> cat.skills == [] end)

    {:noreply, assign(reset_skill_form(socket), skill_mode: :picker, skill_catalog: catalog)}
  end

  def handle_event("cancel_skill", _params, socket) do
    {:noreply, reset_skill_form(socket)}
  end

  def handle_event("pick_catalog_skill", %{"skill-id" => skill_id}, socket) do
    skill = Catalog.load_skill(skill_id)

    {:noreply,
     assign(socket,
       skill_mode: :form,
       editing_skill: nil,
       skill_id: skill["id"],
       skill_title: skill["title"] || "",
       skill_description: skill["description"] || "",
       skill_body: skill["body"] || "",
       skill_always_apply: false
     )}
  end

  def handle_event("custom_skill", _params, socket) do
    {:noreply, assign(reset_skill_form(socket), skill_mode: :form)}
  end

  def handle_event("edit_skill", %{"skill-id" => skill_id}, socket) do
    skill = Enum.find(socket.assigns.team.skills, &(&1["id"] == skill_id))

    if skill do
      {:noreply,
       assign(socket,
         skill_mode: :form,
         editing_skill: skill_id,
         skill_id: skill["id"],
         skill_title: skill["title"] || "",
         skill_description: skill["description"] || "",
         skill_body: skill["body"] || "",
         skill_always_apply: skill["alwaysApply"] == true
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_skill_field", %{"field" => field, "value" => value}, socket) do
    case field do
      "id" -> {:noreply, assign(socket, skill_id: value)}
      "title" -> {:noreply, assign(socket, skill_title: value)}
      "description" -> {:noreply, assign(socket, skill_description: value)}
      "body" -> {:noreply, assign(socket, skill_body: value)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_skill_always_apply", _params, socket) do
    {:noreply, assign(socket, skill_always_apply: !socket.assigns.skill_always_apply)}
  end

  def handle_event("save_skill", _params, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team
      id = String.trim(socket.assigns.skill_id)
      title = String.trim(socket.assigns.skill_title)
      body = String.trim(socket.assigns.skill_body)
      description = String.trim(socket.assigns.skill_description)
      always_apply = socket.assigns.skill_always_apply

      cond do
        id == "" or body == "" ->
          {:noreply, put_flash(socket, :error, "Skill ID and body are required.")}

        not Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/, id) ->
          {:noreply, put_flash(socket, :error, "Skill ID must be alphanumeric (hyphens and underscores allowed).")}

        true ->
          new_skill =
            %{"id" => id, "body" => body}
            |> then(fn s -> if title != "", do: Map.put(s, "title", title), else: s end)
            |> then(fn s -> if description != "", do: Map.put(s, "description", description), else: s end)
            |> then(fn s -> if always_apply, do: Map.put(s, "alwaysApply", true), else: s end)

          existing_skills = team.skills
          editing = socket.assigns.editing_skill

          # Check for duplicate ID (unless editing that same skill)
          duplicate = Enum.any?(existing_skills, fn s -> s["id"] == id and s["id"] != editing end)

          if duplicate do
            {:noreply, put_flash(socket, :error, "A skill with ID \"#{id}\" already exists.")}
          else
            updated_skills =
              if editing do
                Enum.map(existing_skills, fn s ->
                  if s["id"] == editing, do: new_skill, else: s
                end)
              else
                existing_skills ++ [new_skill]
              end

            case team |> Team.changeset(%{skills: updated_skills}) |> Repo.update() do
              {:ok, updated_team} ->
                {:noreply,
                 reset_skill_form(
                   assign(socket, team: Repo.preload(updated_team, :members, force: true))
                 )}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to save skill.")}
            end
          end
      end
    end)
  end

  def handle_event("delete_skill", %{"skill-id" => skill_id}, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team
      updated_skills = Enum.reject(team.skills, &(&1["id"] == skill_id))

      # Also remove the skill from any members that have it
      team.members
      |> Enum.filter(fn m -> skill_id in (m.skills || []) end)
      |> Enum.each(fn m ->
        new_skills = List.delete(m.skills || [], skill_id)
        m |> Member.changeset(%{skills: new_skills}) |> Repo.update()
      end)

      case team |> Team.changeset(%{skills: updated_skills}) |> Repo.update() do
        {:ok, updated_team} ->
          {:noreply,
           reset_skill_form(
             assign(socket, team: Repo.preload(updated_team, :members, force: true))
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete skill.")}
      end
    end)
  end

  # --- Invite generation ---

  def handle_event("generate_invite", _params, socket) do
    team = socket.assigns.team

    case find_user_token_for_team(socket.assigns, team.id) do
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Unable to generate invite. No linked machine found for this team."
         )}

      token ->
        case Teams.create_invite(token, 24, team.id) do
          {:ok, code, expires_at} ->
            invites = load_active_invites(team.id)

            {:noreply,
             assign(socket,
               invites: invites,
               generated_invite: %{code: code, expires_at: expires_at}
             )}

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

  defp reset_skill_form(socket) do
    assign(socket,
      skill_mode: nil,
      skill_catalog: nil,
      editing_skill: nil,
      skill_id: "",
      skill_title: "",
      skill_description: "",
      skill_body: "",
      skill_always_apply: false
    )
  end

  defp member_path(team_id, member_id, nil), do: "/teams/#{team_id}/members/#{member_id}"
  defp member_path(team_id, member_id, code), do: "/teams/#{team_id}/members/#{member_id}?invite=#{code}"

  defp truncate_token(token) when is_binary(token), do: String.slice(token, 0, 12) <> "..."
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

  defp time_remaining(expires_at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(expires_at, now, :second)

    cond do
      diff <= 0 -> "expired"
      diff < 3600 -> "#{div(diff, 60)} min"
      diff < 86400 -> "#{div(diff, 3600)} hr"
      true -> "#{div(diff, 86400)} days"
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-8">
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
      <div>
        <div :if={@editing_section != "name"} class="flex items-center gap-3">
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
        <div :if={@editing_section == "name"} class="flex items-center gap-2">
          <input
            type="text"
            value={@edit_team_name}
            phx-keyup="update_edit_team_name"
            phx-debounce="300"
            maxlength="64"
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

      <%!-- Join command (shown when invite code is present) --%>
      <div :if={@invite_code}>
        <p class="text-sm text-base-content/50 mb-3">
          Run this command to join the team. Expires in <span class="text-base-content/70 font-medium"><%= time_remaining(@invite_access.expires_at) %></span>.
        </p>
        <p :if={!@clerk_email} class="text-sm text-base-content/50 mb-4">
          For permanent access, <a href={~p"/"} class="text-primary font-medium hover:text-primary/80 transition-colors">sign in or create an account</a>.
        </p>
        <div class="terminal-block rounded-lg overflow-hidden">
          <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5">
            <div class="flex items-center gap-2">
              <div class="flex gap-1.5">
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
              </div>
              <span class="text-[10px] font-mono text-white/25 ml-2">terminal</span>
            </div>
            <button
              id="copy-btn"
              phx-click={JS.dispatch("trc:copy", detail: %{text: "npx teamrc join #{@invite_code}"})}
              class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
            >
              copy
            </button>
          </div>
          <div class="p-4">
            <div class="flex items-start gap-2">
              <span class="text-white/30 font-mono text-sm select-none">$</span>
              <code class="text-emerald-400 text-sm font-mono break-all select-all">npx teamrc join <%= @invite_code %></code>
            </div>
          </div>
        </div>
      </div>

      <%!-- Members --%>
      <section>
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Members
            <span class="font-mono text-base-content/30 ml-1"><%= length(@team.members) %></span>
          </p>
        </div>

        <div class="space-y-2">
          <a
            :for={member <- @team.members}
            href={member_path(@team.id, member.id, @invite_code)}
            class="trc-focus group block rounded-lg border border-base-300 bg-base-100 p-4 hover:border-primary/20 transition-colors"
          >
            <div class="flex items-start justify-between">
              <div>
                <span class="font-mono font-semibold text-sm text-base-content"><%= member.name %></span>
                <p class="text-xs text-base-content/60 mt-0.5"><%= member.role %></p>
              </div>
              <svg class="h-4 w-4 text-base-content/20 group-hover:text-primary/50 mt-0.5 shrink-0 transition-colors" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
              </svg>
            </div>
            <div :if={member.skills != []} class="flex flex-wrap gap-1 mt-2">
              <span
                :for={skill_id <- member.skills}
                class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/50"
              >
                <%= skill_id %>
              </span>
            </div>
          </a>
        </div>

        <%!-- Add member --%>
        <div :if={@can_edit} class="mt-3">
          <button
            :if={!@show_add_member}
            phx-click="toggle_add_member"
            class="trc-focus inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
            </svg>
            Add team member
          </button>

          <div :if={@show_add_member} class="rounded-lg border border-base-300 bg-base-200/30 p-3 space-y-2 animate-[fadeIn_150ms_ease-out]">
            <div class="flex gap-2">
              <input
                type="text"
                value={@new_member_name}
                phx-keyup="update_new_member_name"
                phx-debounce="300"
                phx-mounted={JS.focus()}
                maxlength="64"
                placeholder="agent-name"
                class="trc-focus flex-1 rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
              />
              <input
                type="text"
                value={@new_member_role}
                phx-keyup="update_new_member_role"
                phx-debounce="300"
                maxlength="256"
                placeholder="Role description"
                class="trc-focus flex-[2] rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
              />
            </div>
            <div class="flex gap-2">
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
                Add
              </button>
              <button
                phx-click="toggle_add_member"
                class="trc-focus rounded px-3 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/70 transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </section>

      <%!-- Skills --%>
      <section>
        <div class="flex items-center justify-between mb-1">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Skills
            <span class="font-mono text-base-content/30 ml-1"><%= length(@team.skills) %></span>
          </p>
        </div>
        <p class="text-xs text-base-content/40 mb-3">
          Reusable instructions that can be assigned to individual agents. Skills marked <span class="font-semibold">all agents</span> apply to every agent automatically.
          <a href={~p"/guide#skills"} class="text-primary/60 hover:text-primary transition-colors">Learn more</a>
        </p>

        <%!-- Existing skills list --%>
        <%= if @team.skills != [] do %>
          <div class="space-y-1.5">
            <%= for skill <- @team.skills do %>
              <div class="group flex items-start justify-between rounded-lg border border-base-300 bg-base-100 px-3 py-2.5">
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-mono font-medium text-base-content"><%= skill["id"] %></span>
                    <span :if={skill["title"]} class="text-xs text-base-content/50"><%= skill["title"] %></span>
                    <span
                      :if={skill["alwaysApply"]}
                      class="inline-flex items-center rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary/80"
                    >
                      all agents
                    </span>
                  </div>
                  <p :if={skill["description"]} class="text-xs text-base-content/40 mt-0.5"><%= skill["description"] %></p>
                </div>
                <div :if={@can_edit} class="flex items-center gap-1 ml-2 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    phx-click="edit_skill"
                    phx-value-skill-id={skill["id"]}
                    class="trc-focus rounded p-1 text-base-content/30 hover:text-base-content/60 transition-colors"
                    aria-label="Edit skill"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                    </svg>
                  </button>
                  <button
                    phx-click="delete_skill"
                    phx-value-skill-id={skill["id"]}
                    data-confirm={"Remove skill \"#{skill["id"]}\"? This will also unassign it from all agents."}
                    class="trc-focus rounded p-1 text-base-content/30 hover:text-error transition-colors"
                    aria-label="Delete skill"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div :if={is_nil(@skill_mode)} class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
            <p class="text-xs text-base-content/40">No skills defined. Skills are shared instructions you can assign to specific agents.</p>
          </div>
        <% end %>

        <%!-- Add skill button / picker / form --%>
        <div :if={@can_edit} class="mt-3">
          <%!-- Default: show "Add skill" button --%>
          <button
            :if={is_nil(@skill_mode)}
            phx-click="show_skill_picker"
            class="trc-focus inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
            </svg>
            Add skill
          </button>

          <%!-- Step 1: Skill picker (pre-built catalog + custom option) --%>
          <div :if={@skill_mode == :picker} class="rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-4 animate-[fadeIn_150ms_ease-out]">
            <div class="flex items-center justify-between">
              <p class="text-xs font-medium text-base-content/60">Add a skill</p>
              <button
                phx-click="cancel_skill"
                class="trc-focus text-xs text-base-content/30 hover:text-base-content/50 transition-colors"
              >
                Cancel
              </button>
            </div>

            <%!-- Custom skill option --%>
            <button
              phx-click="custom_skill"
              class="trc-focus w-full text-left rounded-lg border border-base-300 bg-base-100 px-3 py-2.5 hover:border-primary/30 transition-colors"
            >
              <div class="flex items-center gap-2.5">
                <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/40">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
                  </svg>
                </div>
                <div>
                  <span class="text-sm font-medium">Write custom skill</span>
                  <p class="text-xs text-base-content/40">Define your own instructions from scratch</p>
                </div>
              </div>
            </button>

            <%!-- Pre-built skills by category --%>
            <%= for category <- @skill_catalog do %>
              <div>
                <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5"><%= category.label %></p>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                  <%= for skill <- category.skills do %>
                    <button
                      phx-click="pick_catalog_skill"
                      phx-value-skill-id={skill["id"]}
                      class="trc-focus text-left rounded-md border border-base-300 bg-base-100 px-2.5 py-2 hover:border-primary/30 transition-colors"
                    >
                      <span class="text-xs font-mono font-medium text-base-content truncate"><%= skill["id"] %></span>
                      <p :if={skill["description"]} class="text-[11px] text-base-content/40 mt-0.5 line-clamp-1"><%= skill["description"] %></p>
                      <p :if={is_nil(skill["description"]) && skill["title"]} class="text-[11px] text-base-content/40 mt-0.5"><%= skill["title"] %></p>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @skill_catalog == [] do %>
              <p class="text-xs text-base-content/40 text-center py-2">All available pre-built skills have already been added.</p>
            <% end %>
          </div>

          <%!-- Step 2: Skill form (for custom or pre-filled from catalog) --%>
          <div :if={@skill_mode == :form} class="rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-3 animate-[fadeIn_150ms_ease-out]">
            <div class="flex items-center justify-between">
              <p class="text-xs font-medium text-base-content/60">
                <%= if @editing_skill, do: "Edit skill", else: "New skill" %>
              </p>
              <button
                phx-click="cancel_skill"
                class="trc-focus text-xs text-base-content/30 hover:text-base-content/50 transition-colors"
              >
                Cancel
              </button>
            </div>

            <div class="grid grid-cols-2 gap-2">
              <div>
                <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">ID</label>
                <input
                  type="text"
                  value={@skill_id}
                  phx-keyup="update_skill_field"
                  phx-value-field="id"
                  phx-debounce="300"
                  maxlength="64"
                  placeholder="code-style"
                  disabled={@editing_skill != nil}
                  class={[
                    "trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors",
                    if(@editing_skill, do: "opacity-50 cursor-not-allowed", else: "")
                  ]}
                />
              </div>
              <div>
                <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">Title <span class="text-base-content/25">(optional)</span></label>
                <input
                  type="text"
                  value={@skill_title}
                  phx-keyup="update_skill_field"
                  phx-value-field="title"
                  phx-debounce="300"
                  maxlength="128"
                  placeholder="Code Style Guide"
                  class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                />
              </div>
            </div>

            <div>
              <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">Description <span class="text-base-content/25">(optional)</span></label>
              <input
                type="text"
                value={@skill_description}
                phx-keyup="update_skill_field"
                phx-value-field="description"
                phx-debounce="300"
                maxlength="256"
                placeholder="Enforces consistent code formatting and naming conventions"
                class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
              />
            </div>

            <div>
              <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">Body</label>
              <textarea
                phx-keyup="update_skill_field"
                phx-value-field="body"
                phx-debounce="500"
                rows="6"
                placeholder="The instructions for this skill in markdown..."
                class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-2 text-sm font-mono placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors resize-y"
              ><%= @skill_body %></textarea>
            </div>

            <div class="flex items-center gap-2">
              <button
                phx-click="toggle_skill_always_apply"
                class={[
                  "trc-focus relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out",
                  if(@skill_always_apply, do: "bg-primary", else: "bg-base-300")
                ]}
                role="switch"
                aria-checked={to_string(@skill_always_apply)}
              >
                <span class={[
                  "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                  if(@skill_always_apply, do: "translate-x-4", else: "translate-x-0")
                ]} />
              </button>
              <span class="text-xs text-base-content/60">Apply to all agents</span>
              <span class="text-[10px] text-base-content/30">(otherwise, assign per-agent on their detail page)</span>
            </div>

            <div class="flex gap-2 pt-1">
              <button
                phx-click="save_skill"
                disabled={@skill_id == "" || @skill_body == ""}
                class={[
                  "trc-focus rounded px-3 py-1.5 text-xs font-semibold transition-all",
                  if(@skill_id == "" || @skill_body == "",
                    do: "bg-base-300 text-base-content/30 cursor-not-allowed",
                    else: "bg-primary text-primary-content hover:brightness-110"
                  )
                ]}
              >
                <%= if @editing_skill, do: "Update skill", else: "Add skill" %>
              </button>
              <button
                phx-click="cancel_skill"
                class="trc-focus rounded px-3 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/70 transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </section>

      <%!-- Knowledge --%>
      <section>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">Knowledge</p>
        <div :if={@team.knowledge && @team.knowledge != ""} class="rounded-lg border border-base-300 bg-base-100 px-4 py-3">
          <pre class="text-xs font-mono text-base-content/70 whitespace-pre-wrap break-words"><%= @team.knowledge %></pre>
        </div>
        <div :if={is_nil(@team.knowledge) || @team.knowledge == ""} class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
          <p class="text-xs text-base-content/40">No knowledge yet. Knowledge is managed via the CLI. <a href={~p"/guide#knowledge"} class="text-primary/60 hover:text-primary transition-colors">Learn more</a></p>
        </div>
      </section>

      <%!-- Active machines (visible to all) --%>
      <section>
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-3">
          Active Machines
          <span class="font-mono text-base-content/30 ml-1"><%= length(@machines) %></span>
        </p>

        <div :if={@machines == []} class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
          <p class="text-xs text-base-content/40">No machines syncing this team yet. Run the join command to connect.</p>
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
                <code :if={@can_edit_owner} class="text-[10px] font-mono text-base-content/25"><%= truncate_token(machine.token) %></code>
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

      <%!-- Participants (owner only) --%>
      <section :if={@can_edit_owner && @participants != []}>
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

      <%!-- Invites (owner only) --%>
      <section :if={@can_edit_owner}>
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Invites
            <span class="font-mono text-base-content/30 ml-1"><%= length(@invites) %></span>
          </p>
          <button
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
            Expires in <%= time_remaining(@generated_invite.expires_at) %>
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
              expires in <%= time_remaining(invite.expires_at) %>
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
