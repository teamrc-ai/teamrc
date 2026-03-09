defmodule TeamrcWeb.MemberDetailLive do
  use TeamrcWeb, :live_view

  alias Teamrc.{Accounts, Repo}
  alias Teamrc.Schema.{Team, Invite, Member}
  import Ecto.Query
  import TeamrcWeb.LiveHelpers

  # --- Mount ---

  @impl true
  def mount(%{"team_id" => team_id, "member_id" => member_id} = params, _session, socket) do
    team = Repo.get(Team, team_id) |> maybe_preload()
    member = team && Enum.find(team.members, &(&1.id == member_id))
    invite_code = params["invite"]

    cond do
      is_nil(team) ->
        {:ok, socket |> put_flash(:error, "Team not found.") |> redirect(to: ~p"/new")}

      is_nil(member) ->
        {:ok,
         socket
         |> put_flash(:error, "Member not found.")
         |> redirect(to: "/teams/#{team_id}")}

      true ->
        owner_access = Accounts.is_team_participant?(socket.assigns[:clerk_user_id], team.id)
        invite_access = load_valid_invite(team.id, invite_code)

        can_view =
          owner_access or
            team.visibility == "public" or
            not is_nil(invite_access)

        if can_view do
          can_edit = owner_access or not is_nil(invite_access)

          {:ok,
           assign(socket,
             page_title: "#{member.name} — #{team.name}",
             team: team,
             member: member,
             can_edit: can_edit,
             invite_access: invite_access,
             invite_code: invite_code,
             edit_name: member.name,
             edit_role: member.role,
             edit_soul: member.soul || "",
             dirty: false
           )}
        else
          {:ok,
           socket
           |> put_flash(:error, "This team is private.")
           |> redirect(to: "/teams/#{team_id}")}
        end
    end
  end

  defp maybe_preload(nil), do: nil
  defp maybe_preload(team), do: Repo.preload(team, :members)

  @impl true
  def handle_params(_params, uri, socket) do
    query = URI.parse(uri).query
    query_params = if query, do: URI.decode_query(query), else: %{}

    socket =
      case query_params["invite"] do
        nil ->
          socket

        invite_code ->
          team = socket.assigns.team

          case load_valid_invite(team.id, invite_code) do
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

  defp load_valid_invite(_team_id, nil), do: nil

  defp load_valid_invite(team_id, invite_code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.one(
      from(i in Invite,
        where: i.code == ^invite_code and i.team_id == ^team_id and i.expires_at > ^now
      )
    )
  end

  # --- Events ---

  @impl true
  def handle_event("update_name", %{"value" => v}, socket) do
    {:noreply, assign(socket, edit_name: v, dirty: true)}
  end

  def handle_event("update_role", %{"value" => v}, socket) do
    {:noreply, assign(socket, edit_role: v, dirty: true)}
  end

  def handle_event("update_soul", %{"value" => v}, socket) do
    {:noreply, assign(socket, edit_soul: v, dirty: true)}
  end

  def handle_event("save", _params, socket) do
    require_edit_access(socket, fn ->
      member = socket.assigns.member
      team = socket.assigns.team

      # IDOR protection: re-verify member belongs to this team
      case Repo.get(Member, member.id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Member no longer exists.")}

        db_member when db_member.team_id != team.id ->
          {:noreply, put_flash(socket, :error, "Access denied.")}

        db_member ->
          name = String.trim(socket.assigns.edit_name)
          role = String.trim(socket.assigns.edit_role)
          soul = String.trim(socket.assigns.edit_soul)

          if name != "" and role != "" do
            changes = %{
              name: name,
              role: role,
              soul: if(soul != "", do: soul, else: nil)
            }

            case db_member |> Member.changeset(changes) |> Repo.update() do
              {:ok, updated_member} ->
                updated_team = Repo.preload(team, :members, force: true)

                {:noreply,
                 assign(socket,
                   member: updated_member,
                   team: updated_team,
                   dirty: false,
                   page_title: "#{updated_member.name} — #{team.name}"
                 )
                 |> put_flash(:info, "Saved.")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to save changes.")}
            end
          else
            {:noreply, put_flash(socket, :error, "Name and role are required.")}
          end
      end
    end)
  end

  def handle_event("toggle_skill", %{"skill-id" => skill_id}, socket) do
    require_edit_access(socket, fn ->
      member = socket.assigns.member
      team = socket.assigns.team

      # IDOR protection: re-verify member belongs to this team
      case Repo.get(Member, member.id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Member no longer exists.")}

        db_member when db_member.team_id != team.id ->
          {:noreply, put_flash(socket, :error, "Access denied.")}

        db_member ->
          current_skills = db_member.skills || []

          # Validate skill_id exists in team skills
          team_skill_ids = Enum.map(team.skills, & &1["id"])

          if skill_id not in team_skill_ids do
            {:noreply, put_flash(socket, :error, "Invalid skill.")}
          else
            new_skills =
              if skill_id in current_skills do
                List.delete(current_skills, skill_id)
              else
                current_skills ++ [skill_id]
              end

            case db_member |> Member.changeset(%{skills: new_skills}) |> Repo.update() do
              {:ok, updated_member} ->
                updated_team = Repo.preload(team, :members, force: true)
                {:noreply, assign(socket, member: updated_member, team: updated_team)}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to update skills.")}
            end
          end
      end
    end)
  end

  def handle_event("delete_member", _params, socket) do
    require_edit_access(socket, fn ->
      member = socket.assigns.member
      team = socket.assigns.team

      # IDOR protection: re-verify member belongs to this team
      case Repo.get(Member, member.id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Member no longer exists.")}

        db_member when db_member.team_id != team.id ->
          {:noreply, put_flash(socket, :error, "Access denied.")}

        db_member ->
          Repo.delete(db_member)
          back = team_path(team.id, socket.assigns.invite_code)
          {:noreply, socket |> put_flash(:info, "Member removed.") |> redirect(to: back)}
      end
    end)
  end

  # --- Helpers ---

  defp team_path(team_id, nil), do: "/teams/#{team_id}"
  defp team_path(team_id, code), do: "/teams/#{team_id}?invite=#{code}"

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Back navigation --%>
      <a
        href={team_path(@team.id, @invite_code)}
        class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-base-content/40 hover:text-base-content/70 transition-colors rounded px-1 -ml-1"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-3.5 w-3.5"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z"
            clip-rule="evenodd"
          />
        </svg>
        <span class="font-mono">{@team.name}</span>
      </a>

      <%!-- Header --%>
      <div>
        <%= if @can_edit do %>
          <div class="space-y-3">
            <div>
              <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">
                Name
              </label>
              <input
                type="text"
                value={@edit_name}
                phx-keyup="update_name"
                phx-debounce="300"
                maxlength="64"
                class="trc-focus w-full rounded-lg border border-base-300 bg-base-100 px-4 py-2.5 text-xl font-mono font-bold placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
              />
            </div>
            <div>
              <label class="block text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">
                Role
              </label>
              <input
                type="text"
                value={@edit_role}
                phx-keyup="update_role"
                phx-debounce="300"
                maxlength="256"
                class="trc-focus w-full rounded-lg border border-base-300 bg-base-100 px-4 py-2.5 text-sm placeholder:text-base-content/30 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
              />
            </div>
          </div>
        <% else %>
          <h1 class="text-2xl font-bold tracking-tight font-mono">{@member.name}</h1>
          <p class="text-sm text-base-content/60 mt-1">{@member.role}</p>
        <% end %>
      </div>

      <%!-- Soul / Instructions --%>
      <section>
        <div class="flex items-center gap-2 mb-3">
          <h2 class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
            Instructions
          </h2>
          <a
            href={~p"/guide#instructions"}
            class="text-[10px] text-primary/50 hover:text-primary transition-colors"
          >
            ?
          </a>
        </div>

        <%= if @can_edit do %>
          <textarea
            phx-keyup="update_soul"
            phx-debounce="500"
            rows="20"
            placeholder="Write this agent's personality, behavioral guidelines, and instructions in markdown..."
            class="trc-focus soul-editor w-full rounded-lg border border-base-300 bg-base-200/30 p-5 text-sm font-mono text-base-content/80 leading-relaxed placeholder:text-base-content/30 focus:border-primary/40 focus:ring-1 focus:ring-primary/20 transition-colors resize-y"
          ><%= @edit_soul %></textarea>
        <% else %>
          <div class="soul-editor rounded-lg border border-base-300 bg-base-200/30">
            <pre
              :if={@member.soul && @member.soul != ""}
              class="p-5 text-sm font-mono text-base-content/80 whitespace-pre-wrap break-words leading-relaxed"
            ><%= @member.soul %></pre>
            <p
              :if={is_nil(@member.soul) || @member.soul == ""}
              class="p-5 text-sm text-base-content/40 italic"
            >
              No instructions defined for this agent.
            </p>
          </div>
        <% end %>
      </section>

      <%!-- Skills --%>
      <section>
        <h2 class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1">
          Skills
          <span class="font-mono text-base-content/30 ml-1">{length(@member.skills || [])}</span>
        </h2>
        <p class="text-xs text-base-content/40 mb-3">
          Toggle skills to assign them to this agent. Skills marked
          <span class="font-semibold">all agents</span>
          are automatically included and can't be removed.
          <a href={~p"/guide#skills"} class="text-primary/60 hover:text-primary transition-colors">
            Learn more
          </a>
        </p>

        <%= if @team.skills != [] do %>
          <div class="space-y-1.5">
            <%= for skill <- @team.skills do %>
              <% assigned = skill["id"] in (@member.skills || []) %>
              <% always_on = skill["alwaysApply"] %>

              <%= if @can_edit && !always_on do %>
                <button
                  phx-click="toggle_skill"
                  phx-value-skill-id={skill["id"]}
                  class={[
                    "trc-focus w-full text-left flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-all",
                    if(assigned,
                      do: "bg-primary/10 border border-primary/20",
                      else: "bg-base-200/30 border border-base-300 hover:border-primary/20"
                    )
                  ]}
                >
                  <div class={[
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors",
                    if(assigned,
                      do: "bg-primary border-primary text-primary-content",
                      else: "border-base-content/20"
                    )
                  ]}>
                    <svg
                      :if={assigned}
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-3 w-3"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <span class="font-mono font-medium text-xs">{skill["id"]}</span>
                      <span :if={skill["title"]} class="text-xs text-base-content/50">
                        {skill["title"]}
                      </span>
                    </div>
                    <p :if={skill["description"]} class="text-xs text-base-content/40 mt-0.5">
                      {skill["description"]}
                    </p>
                  </div>
                </button>
              <% else %>
                <div class={[
                  "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm",
                  if(assigned || always_on,
                    do: "bg-primary/5 border border-primary/10",
                    else: "bg-base-200/20 border border-base-300"
                  )
                ]}>
                  <div class={[
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                    if(assigned || always_on,
                      do: "bg-primary/60 border-primary/60 text-primary-content",
                      else: "border-base-content/15"
                    )
                  ]}>
                    <svg
                      :if={assigned || always_on}
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-3 w-3"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <span class="font-mono font-medium text-xs">{skill["id"]}</span>
                      <span :if={skill["title"]} class="text-xs text-base-content/50">
                        {skill["title"]}
                      </span>
                      <span
                        :if={always_on}
                        class="inline-flex items-center rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary/70"
                      >
                        all agents
                      </span>
                    </div>
                    <p :if={skill["description"]} class="text-xs text-base-content/40 mt-0.5">
                      {skill["description"]}
                    </p>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        <% else %>
          <p class="text-xs text-base-content/40">
            No skills defined for this team. Add skills on the team dashboard.
          </p>
        <% end %>
      </section>

      <%!-- Actions --%>
      <div :if={@can_edit} class="flex items-center justify-between pt-4 border-t border-base-200">
        <button
          :if={@dirty}
          phx-click="save"
          class="trc-focus rounded-lg bg-primary px-5 py-2 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
        >
          Save changes
        </button>
        <span :if={!@dirty} class="text-xs text-base-content/30">All changes saved</span>

        <button
          phx-click="delete_member"
          data-confirm="Are you sure you want to remove this member?"
          class="trc-focus rounded-lg px-4 py-2 text-xs font-medium text-base-content/30 hover:text-error hover:bg-error/10 transition-colors"
        >
          Remove member
        </button>
      </div>
    </div>
    """
  end
end
