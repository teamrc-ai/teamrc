defmodule TeamrcWeb.TeamDetailLive do
  use TeamrcWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Teamrc.{Accounts, Catalog, Teams}
  import TeamrcWeb.LiveHelpers

  @max_members 20
  @max_skill_body_bytes 10_000
  @max_skills 50

  # --- Mount ---

  @impl true
  def mount(%{"id" => team_id}, session, socket) do
    current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    creator_sessions = session["creator_sessions"] || %{}
    socket = assign(socket, current_user: current_user, creator_sessions: creator_sessions)

    case load_team(team_id, socket.assigns) do
      {:ok, %{access_level: :private_gate}} ->
        {:ok,
         assign(socket,
           default_form_assigns() ++
             [
               page_title: "Private Team",
               team_id: team_id,
               access_level: :private_gate,
               can_edit: false,
               is_owner: false,
               team: nil,
               clone_token: nil,
               participants: [],
               invites: []
             ]
         )}

      {:ok, data} ->
        {:ok,
         assign(socket,
           default_form_assigns() ++
             [
               page_title: data.team.name,
               team_id: team_id,
               team: data.team,
               access_level: data.access_level,
               can_edit: data.access_level in [:owner, :participant],
               is_owner: data.access_level == :owner,
               is_creator_session: data[:is_creator_session] == true,
               clone_token: data.clone_token,
               participants: data.participants,
               invites: data.invites,
               edit_team_name: data.team.name
             ]
         )}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Team not found.")
         |> redirect(to: ~p"/new")}
    end
  end

  defp default_form_assigns do
    [
      invite_access: nil,
      invite_code: nil,
      editing_section: nil,
      edit_team_name: "",
      member_mode: nil,
      member_catalog: nil,
      new_member_name: "",
      new_member_role: "",
      new_member_soul: "",
      new_member_skills: [],
      generating_invite: false,
      generated_invite: nil,
      skill_mode: nil,
      skill_catalog: nil,
      editing_skill: nil,
      skill_id: "",
      skill_title: "",
      skill_description: "",
      skill_body: "",
      skill_always_apply: false,
      show_share_modal: false,
      show_claim_form: false,
      claim_secret_input: ""
    ]
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Check for invite code in query params (e.g. /teams/:id?invite=CODE) or flash
    invite_code = params["invite"] || socket.assigns.flash["invite_code"]

    socket =
      case invite_code do
        nil ->
          socket

        invite_code ->
          case socket.assigns.access_level do
            :private_gate ->
              # Private team with invite code - validate and load team
              reload_with_invite(socket, invite_code, socket.assigns.team_id)

            _ ->
              # Public or owner - just validate the invite for the banner
              team = socket.assigns.team

              case Teams.get_valid_invite(team.id, invite_code) do
                nil ->
                  put_flash(socket, :error, "This invite code has expired or is invalid.")

                invite ->
                  assign(socket, invite_access: invite, invite_code: invite_code)
              end
          end
      end

    {:noreply, socket}
  end

  defp reload_with_invite(socket, invite_code, team_id) do
    case Teams.get_valid_invite_with_team(team_id, invite_code) do
      nil ->
        put_flash(socket, :error, "This invite code has expired or is invalid.")

      %{team: team} = invite ->
        assign(socket,
          team: team,
          page_title: team.name,
          access_level: :viewer,
          can_edit: false,
          is_owner: false,
          clone_token: nil,
          participants: [],
          invites: [],
          invite_access: invite,
          invite_code: invite_code,
          edit_team_name: team.name
        )
    end
  end

  # --- Data loading ---

  defp load_team(team_id, assigns) do
    team = Teams.get_team_by_id(team_id)

    case team do
      nil ->
        :not_found

      team ->
        current_scope = assigns[:current_scope]
        current_user = current_scope && current_scope.user
        user_id = current_user && current_user.id
        is_participant = Accounts.is_team_participant?(user_id, team.id)

        # Check creator session: the browser that created this team gets owner access
        creator_sessions = assigns[:creator_sessions] || %{}
        creator_token = Map.get(creator_sessions, team_id)
        is_creator = is_binary(creator_token) && Teams.verify_creator_token(team_id, creator_token)

        access_level =
          cond do
            is_participant && user_id && user_id == team.owner_user_id -> :owner
            is_participant -> :participant
            is_creator -> :owner
            team.visibility == "public" -> :viewer
            true -> :private_gate
          end

        case access_level do
          :private_gate ->
            {:ok, %{access_level: :private_gate}}

          _ ->
            raw_participants =
              if is_participant, do: Accounts.resolve_participants(team.id), else: []

            # Security: hash participant emails before storing in socket assigns
            participants =
              Enum.map(raw_participants, fn
                "anonymous" -> "anonymous"
                email -> Teamrc.PII.email_hash(email) || "anonymous"
              end)

            has_team_access = is_participant || is_creator
            invites = if has_team_access, do: Teams.list_active_invites(team.id), else: []
            clone_token = if has_team_access, do: team.clone_token, else: nil

            {:ok,
             %{
               team: team,
               access_level: access_level,
               is_creator_session: is_creator,
               participants: participants,
               invites: invites,
               clone_token: clone_token
             }}
        end
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
        case Teams.update_team_name(team, new_name) do
          {:ok, updated_team} ->
            {:noreply,
             socket
             |> assign(
               team: updated_team,
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

  def handle_event("show_member_picker", _params, socket) do
    existing_names = MapSet.new(socket.assigns.team.members, & &1.name)

    catalog =
      Catalog.list_agent_categories()
      |> Enum.map(fn cat ->
        agents =
          cat["agents"]
          |> Enum.map(fn name -> Catalog.load_agent(name) end)
          |> Enum.reject(fn a -> MapSet.member?(existing_names, a["name"]) end)

        %{id: cat["id"], label: cat["label"], agents: agents}
      end)
      |> Enum.reject(fn cat -> cat.agents == [] end)

    {:noreply,
     assign(socket,
       member_mode: :picker,
       member_catalog: catalog,
       new_member_name: "",
       new_member_role: "",
       new_member_soul: "",
       new_member_skills: []
     )}
  end

  def handle_event("cancel_member", _params, socket) do
    {:noreply,
     assign(socket,
       member_mode: nil,
       member_catalog: nil,
       new_member_name: "",
       new_member_role: "",
       new_member_soul: "",
       new_member_skills: []
     )}
  end

  def handle_event("pick_catalog_member", %{"agent-name" => agent_name}, socket) do
    if Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/, agent_name) do
      agent = Catalog.load_agent(agent_name)
      recommended_skills = Catalog.agent_recommended_skills(agent_name)

      {:noreply,
       assign(socket,
         member_mode: :form,
         new_member_name: agent["name"],
         new_member_role: agent["role"],
         new_member_soul: agent["soul"] || "",
         new_member_skills: recommended_skills
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("custom_member", _params, socket) do
    {:noreply,
     assign(socket,
       member_mode: :form,
       new_member_name: "",
       new_member_role: "",
       new_member_soul: "",
       new_member_skills: []
     )}
  end

  def handle_event("add_member", _params, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team

      if length(team.members) >= @max_members do
        {:noreply, put_flash(socket, :error, "Maximum #{@max_members} members reached.")}
      else
        name = String.trim(socket.assigns.new_member_name)
        role = String.trim(socket.assigns.new_member_role)
        soul = String.trim(socket.assigns.new_member_soul)

        if name != "" and role != "" do
          recommended = socket.assigns.new_member_skills
          existing_ids = MapSet.new(team.skills, & &1["id"])

          # Add missing recommended skills to the team
          new_team_skills =
            recommended
            |> Enum.reject(&MapSet.member?(existing_ids, &1))
            |> Enum.flat_map(fn skill_id ->
              case safe_load_skill(skill_id) do
                nil -> []
                skill -> [catalog_skill_to_map(skill)]
              end
            end)

          team =
            if new_team_skills != [] do
              case Teams.update_team_skills(team, team.skills ++ new_team_skills) do
                {:ok, t} -> t
                {:error, _} -> team
              end
            else
              team
            end

          # Only assign skills that actually exist on the team now
          all_team_skill_ids = MapSet.new(team.skills, & &1["id"])
          member_skills = Enum.filter(recommended, &MapSet.member?(all_team_skill_ids, &1))

          attrs = %{name: name, role: role, skills: member_skills}
          attrs = if soul != "", do: Map.put(attrs, :soul, soul), else: attrs

          case Teams.add_member(team.id, attrs) do
            {:ok, _member} ->
              updated_team = Teams.reload_team_with_members(team)

              {:noreply,
               assign(socket,
                 team: updated_team,
                 new_member_name: "",
                 new_member_role: "",
                 new_member_soul: "",
                 new_member_skills: [],
                 member_mode: nil,
                 member_catalog: nil
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
    if Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/, skill_id) do
      skill = Catalog.load_skill(skill_id)

      {:noreply,
       assign(socket,
         skill_mode: :form,
         editing_skill: nil,
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
          {:noreply,
           put_flash(
             socket,
             :error,
             "Skill ID must be alphanumeric (hyphens and underscores allowed)."
           )}

        byte_size(body) > @max_skill_body_bytes ->
          {:noreply, put_flash(socket, :error, "Skill body exceeds #{@max_skill_body_bytes} bytes.")}

        !socket.assigns.editing_skill and length(team.skills) >= @max_skills ->
          {:noreply, put_flash(socket, :error, "Team may have at most #{@max_skills} skills.")}

        true ->
          existing_skills = team.skills
          editing = socket.assigns.editing_skill

          # When editing, start from the existing skill to preserve fields
          # not exposed in the web form (globs, userInvocable)
          base_skill =
            if editing do
              Enum.find(existing_skills, %{}, fn s -> s["id"] == editing end)
            else
              %{}
            end

          new_skill =
            base_skill
            |> Map.merge(%{"id" => id, "body" => body})
            |> then(fn s -> if title != "", do: Map.put(s, "title", title), else: Map.delete(s, "title") end)
            |> then(fn s ->
              if description != "", do: Map.put(s, "description", description), else: Map.delete(s, "description")
            end)
            |> then(fn s -> if always_apply, do: Map.put(s, "alwaysApply", true), else: Map.delete(s, "alwaysApply") end)

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

            case Teams.update_team_skills(team, updated_skills) do
              {:ok, updated_team} ->
                {:noreply,
                 reset_skill_form(
                   assign(socket, team: updated_team)
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

      case Teams.delete_skill(team, skill_id) do
        {:ok, updated_team} ->
          {:noreply,
           reset_skill_form(
             assign(socket, team: updated_team)
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete skill.")}
      end
    end)
  end

  # --- Invite generation ---

  def handle_event("generate_invite", _params, socket) do
    require_edit_access(socket, fn ->
      team = socket.assigns.team

      # Try token-based invite first; fall back to direct team_id invite for web-only owners
      invite_result =
        case find_user_token_for_team(socket.assigns, team.id) do
          nil ->
            if socket.assigns.is_owner do
              Teams.create_invite_by_team_id(team.id, 24)
            else
              :error
            end

          token ->
            Teams.create_invite(token, 24, team.id)
        end

      case invite_result do
        {:ok, code, expires_at} ->
          invites = Teams.list_active_invites(team.id)

          {:noreply,
           assign(socket,
             invites: invites,
             generated_invite: %{code: code, expires_at: expires_at}
           )}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to generate invite.")}
      end
    end)
  end

  def handle_event("dismiss_generated_invite", _params, socket) do
    {:noreply, assign(socket, generated_invite: nil)}
  end

  def handle_event("revoke_invite", %{"id" => invite_id}, socket) do
    require_edit_access(socket, fn ->
      case Teams.revoke_invite(invite_id, socket.assigns.team.id) do
        {:ok, _} ->
          invites = Teams.list_active_invites(socket.assigns.team.id)
          {:noreply, assign(socket, invites: invites)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to revoke invite.")}
      end
    end)
  end

  def handle_event("open_share_modal", _params, socket) do
    if not socket.assigns.is_owner do
      {:noreply, put_flash(socket, :error, "Only the team owner can share this team.")}
    else
      {:noreply, assign(socket, show_share_modal: true)}
    end
  end

  def handle_event("close_share_modal", _params, socket) do
    {:noreply, assign(socket, show_share_modal: false)}
  end

  def handle_event("confirm_share", _params, socket) do
    set_visibility_result(socket, "public")
    |> case do
      {:noreply, socket} -> {:noreply, assign(socket, show_share_modal: false)}
    end
  end

  def handle_event("stop_sharing", _params, socket) do
    set_visibility_result(socket, "private")
  end

  def handle_event("show_claim_form", _params, socket) do
    {:noreply, assign(socket, show_claim_form: true, claim_secret_input: "")}
  end

  def handle_event("cancel_claim", _params, socket) do
    {:noreply, assign(socket, show_claim_form: false, claim_secret_input: "")}
  end

  def handle_event("update_claim_secret", %{"value" => value}, socket) do
    {:noreply, assign(socket, claim_secret_input: value)}
  end

  def handle_event("submit_claim", _params, socket) do
    current_user = socket.assigns.current_user
    team = socket.assigns.team
    secret = String.trim(socket.assigns.claim_secret_input)

    cond do
      is_nil(current_user) ->
        {:noreply, put_flash(socket, :error, "Sign in to claim ownership.")}

      socket.assigns.access_level != :participant ->
        {:noreply, put_flash(socket, :error, "You don't have permission to claim this team.")}

      secret == "" ->
        {:noreply, put_flash(socket, :error, "Please enter a claim secret.")}

      true ->
        case Teams.claim_ownership_by_user(current_user.id, team.id, secret) do
          {:ok, :claimed} ->
            # Reload with owner access
            case load_team(team.id, socket.assigns) do
              {:ok, data} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Ownership claimed successfully.")
                 |> assign(
                   team: data.team,
                   access_level: data.access_level,
                   can_edit: data.access_level in [:owner, :participant],
                   is_owner: data.access_level == :owner,
                   is_creator_session: data[:is_creator_session] == true,
                   participants: data.participants,
                   invites: data.invites,
                   clone_token: data.clone_token,
                   show_claim_form: false,
                   claim_secret_input: ""
                 )}

              _ ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Ownership claimed.")
                 |> push_navigate(to: ~p"/teams/#{team.id}")}
            end

          {:error, :not_participant} ->
            {:noreply, put_flash(socket, :error, "You don't have permission to claim this team.")}

          {:error, :invalid_secret} ->
            {:noreply, put_flash(socket, :error, "Invalid claim secret.")}

          {:error, :already_claimed} ->
            {:noreply, put_flash(socket, :error, "This team already has an owner.")}
        end
    end
  end

  def handle_event("delete_team", _params, socket) do
    current_user = socket.assigns.current_user
    team = socket.assigns.team

    # Require authenticated owner — creator sessions are not sufficient for deletion
    is_authenticated_owner =
      current_user != nil && team.owner_user_id != nil && current_user.id == team.owner_user_id

    if not is_authenticated_owner do
      {:noreply, put_flash(socket, :error, "Only the team owner can delete this team. Sign in and claim ownership first.")}
    else
      case Teams.delete_team(team.id, current_user.id) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Team deleted.")
           |> push_navigate(to: ~p"/dashboard")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete team.")}
      end
    end
  end

  defp set_visibility_result(socket, new_visibility) do
    if not socket.assigns.is_owner do
      {:noreply, put_flash(socket, :error, "Only the team owner can change visibility.")}
    else
      set_visibility_result_authorized(socket, new_visibility)
    end
  end

  defp set_visibility_result_authorized(socket, new_visibility) do
    team = socket.assigns.team

    # Try token-based first, then account-based, then creator-session-based
    visibility_result =
      case find_user_token_for_team(socket.assigns, team.id) do
        nil ->
          current_user = socket.assigns.current_user
          creator_sessions = socket.assigns[:creator_sessions] || %{}
          creator_token = Map.get(creator_sessions, team.id)

          cond do
            current_user ->
              Teams.set_visibility_by_owner(current_user.id, team.id, new_visibility)
            is_binary(creator_token) ->
              Teams.set_visibility_by_creator(team.id, creator_token, new_visibility)
            true ->
              {:error, :not_authorized}
          end

        token ->
          Teams.set_visibility(token, team.id, new_visibility)
      end

    case visibility_result do
      {:ok, updated_team} ->
        updated_team = Teams.reload_team_with_members(updated_team)
        clone_token = if new_visibility == "public", do: updated_team.clone_token, else: nil

        {:noreply,
         assign(socket,
           team: updated_team,
           clone_token: clone_token
         )}

      {:error, :not_owner} ->
        {:noreply, put_flash(socket, :error, "Only the team owner can change visibility.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update visibility.")}
    end
  end

  defp find_user_token_for_team(assigns, team_id) do
    current_scope = assigns[:current_scope]
    current_user = current_scope && current_scope.user
    if is_nil(current_user), do: nil, else: Teams.find_user_token_for_team(current_user.id, team_id)
  end

  # --- Helpers ---

  defp catalog_skill_to_map(skill) do
    %{"id" => skill["id"], "body" => skill["body"]}
    |> then(fn s -> if skill["title"], do: Map.put(s, "title", skill["title"]), else: s end)
    |> then(fn s ->
      if skill["description"], do: Map.put(s, "description", skill["description"]), else: s
    end)
    |> then(fn s -> if skill["alwaysApply"], do: Map.put(s, "alwaysApply", true), else: s end)
  end

  defp safe_load_skill(skill_id) do
    Catalog.load_skill(skill_id)
  rescue
    _ -> nil
  end

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

  defp share_url(team) do
    TeamrcWeb.Endpoint.url() <> "/t/#{team.clone_token}"
  end

  defp member_path(team_id, member_id, nil), do: "/teams/#{team_id}/members/#{member_id}"

  defp member_path(team_id, member_id, code),
    do: "/teams/#{team_id}/members/#{member_id}?invite=#{code}"

  defp time_remaining(expires_at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(expires_at, now, :second)

    cond do
      diff <= 0 -> "expired"
      diff < 3600 -> "#{div(diff, 60)} min"
      diff < 86400 ->
        hours = div(diff, 3600)
        if hours == 1, do: "1 hour", else: "#{hours} hours"
      true ->
        days = div(diff, 86400)
        if days == 1, do: "1 day", else: "#{days} days"
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @access_level == :private_gate do %>
      <%!-- Private gate wall --%>
      <div class="max-w-md mx-auto mt-16 text-center space-y-4">
        <div class="flex justify-center">
          <div class="flex h-12 w-12 items-center justify-center rounded-full bg-base-200">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6 text-base-content/50"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
              />
            </svg>
          </div>
        </div>
        <h1 class="text-lg font-semibold">This team is private</h1>
        <p class="text-sm text-base-content/60">You need an invite code to view this team.</p>
        <p class="text-xs text-base-content/60">
          Ask the team owner for an invite, or <a
            href={~p"/new"}
            class="text-primary hover:text-primary/80"
          >create your own team</a>.
        </p>
      </div>
    <% else %>
      <div class="max-w-2xl mx-auto space-y-8">
        <%!-- Back link --%>
        <a
          :if={@current_user}
          href={~p"/dashboard"}
          class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors rounded px-1 -ml-1"
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
          Dashboard
        </a>

        <%!-- Team header --%>
        <div>
          <div :if={@editing_section != "name"} class="flex flex-wrap items-center gap-2 sm:gap-3">
            <h1 class="text-2xl font-bold tracking-tight font-mono">{@team.name}</h1>
            <span class={[
              "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium",
              if(@team.visibility == "public",
                do: "bg-emerald-500/10 text-emerald-600",
                else: "bg-base-200 text-base-content/60"
              )
            ]}>
              <svg
                :if={@team.visibility == "private"}
                xmlns="http://www.w3.org/2000/svg"
                class="h-2.5 w-2.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
                />
              </svg>
              <svg
                :if={@team.visibility == "public"}
                xmlns="http://www.w3.org/2000/svg"
                class="h-2.5 w-2.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M13.5 10.5V6.75a4.5 4.5 0 1 1 9 0v3.75M3.75 21.75h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H3.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
                />
              </svg>
              {@team.visibility}
            </span>
            <button
              :if={@is_owner && @team.visibility == "private"}
              phx-click="open_share_modal"
              class="trc-focus inline-flex items-center gap-1.5 rounded-md bg-primary px-3 py-1 text-xs font-semibold text-primary-content hover:brightness-110 transition-all"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M15 8a3 3 0 10-2.977-2.63l-4.94 2.47a3 3 0 100 4.319l4.94 2.47a3 3 0 10.895-1.789l-4.94-2.47a3.027 3.027 0 000-.74l4.94-2.47C13.456 7.68 14.19 8 15 8z" />
              </svg>
              Share
            </button>
            <button
              :if={@is_owner && @team.visibility == "public"}
              phx-click={JS.toggle(to: "#share-panel", display: "block")}
              class="trc-focus inline-flex items-center gap-1.5 rounded-md bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-600 hover:bg-emerald-500/15 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M15 8a3 3 0 10-2.977-2.63l-4.94 2.47a3 3 0 100 4.319l4.94 2.47a3 3 0 10.895-1.789l-4.94-2.47a3.027 3.027 0 000-.74l4.94-2.47C13.456 7.68 14.19 8 15 8z" />
              </svg>
              Sharing
            </button>
            <button
              :if={@can_edit}
              phx-click="toggle_edit"
              phx-value-section="name"
              class="trc-focus rounded p-1 text-base-content/50 hover:text-base-content/60 transition-colors"
              aria-label="Rename team"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </button>
          </div>
          <div :if={@editing_section == "name"} class="flex items-center gap-2">
            <label for="team-name" class="sr-only">Team name</label>
            <input
              id="team-name"
              type="text"
              value={@edit_team_name}
              phx-keyup="update_edit_team_name"
              phx-debounce="300"
              maxlength="64"
              class="trc-focus rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-lg font-mono font-bold focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
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
              class="trc-focus rounded-md px-3 py-1.5 text-sm font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
            >
              Cancel
            </button>
          </div>
          <p class="text-sm text-base-content/60 mt-1 font-mono">{@team.id}</p>
        </div>

        <%!-- Share panel (shown to owners when team is public) --%>
        <section
          :if={@is_owner && @team.visibility == "public" && @team.clone_token}
          id="share-panel"
          style="display: none;"
          class="rounded-lg border border-base-300 bg-base-100 p-5 space-y-4"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-semibold text-base-content">Share this team</p>
            <span class="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10px] font-medium text-emerald-600">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-2.5 w-2.5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
              Public
            </span>
          </div>

          <%!-- Shareable URL with copy button --%>
          <div>
            <label class="block text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1.5">
              Shareable link
            </label>
            <div class="flex items-center gap-2">
              <div class="flex-1 rounded-md border border-base-300 bg-base-200/30 px-3 py-2">
                <code class="text-sm font-mono text-base-content/80 break-all select-all"><%= share_url(@team) %></code>
              </div>
              <button
                phx-click={JS.dispatch("trc:copy", detail: %{text: share_url(@team)})}
                class="trc-focus shrink-0 rounded-md border border-base-300 bg-base-100 px-3 py-2 text-xs font-medium text-base-content/60 hover:text-base-content/80 hover:border-base-400 transition-colors"
                aria-label="Copy share URL"
              >
                Copy
              </button>
            </div>
          </div>

          <%!-- Stop sharing button --%>
          <div class="pt-1 border-t border-base-200">
            <button
              phx-click="stop_sharing"
              data-confirm="Make this team private? The share link will stop working and the team will no longer be clonable."
              class="trc-focus text-xs text-base-content/50 hover:text-red-500 transition-colors"
            >
              Stop sharing
            </button>
          </div>
        </section>

        <%!-- Join command (shown when invite code is present) --%>
        <div :if={@invite_code}>
          <p class="text-sm text-base-content/60 mb-3">
            Run this command to join the team. Invite code expires in <span class="text-base-content/70 font-medium"><%= time_remaining(@invite_access.expires_at) %></span>.
          </p>
          <p :if={!@can_edit} class="text-xs text-base-content/50 mb-3">
            Viewing as guest. Join via the CLI to edit this team.
          </p>
          <p :if={!@current_user} class="text-sm text-base-content/60 mb-4">
            For permanent access, <a
              href={~p"/users/log-in"}
              class="text-primary font-medium hover:text-primary/80 transition-colors"
            >sign in or create an account</a>.
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
                phx-click={
                  JS.dispatch("trc:copy", detail: %{text: "npx @teamrc/cli join #{@invite_code}"})
                }
                class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
                aria-label="Copy join command"
              >
                Copy
              </button>
            </div>
            <div class="p-4">
              <div class="flex items-start gap-2">
                <span class="text-white/30 font-mono text-sm select-none">$</span>
                <code class="text-emerald-400 text-sm font-mono break-all select-all">
                  npx @teamrc/cli join {@invite_code}
                </code>
              </div>
            </div>
          </div>
        </div>

        <%!-- Clone box for public teams (shown to non-participants) --%>
        <section :if={@access_level == :viewer && @team.clone_token}>
          <div class="rounded-lg border border-primary/30 bg-primary/5 p-4 space-y-2">
            <p class="text-xs font-semibold">Clone this team</p>
            <div class="terminal-block rounded-lg overflow-hidden">
              <div class="px-3 py-2">
                <code class="text-emerald-400 text-xs font-mono">
                  npx @teamrc/cli clone {@team.clone_token}
                </code>
              </div>
            </div>
            <p class="text-xs text-base-content/60">
              Copies the team config to your machine (read-only). Run <code class="font-mono text-base-content/60">teamrc pull</code> anytime to get the latest updates.
            </p>
          </div>
        </section>

        <%!-- Members --%>
        <section>
          <div class="flex items-center justify-between mb-3">
            <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
              Members <span class="font-mono text-base-content/50 ml-1">{length(@team.members)}</span>
            </p>
          </div>

          <div class="space-y-2">
            <a
              :for={member <- @team.members}
              href={member_path(@team.id, member.id, @invite_code)}
              class="trc-focus group block rounded-lg border border-base-300 bg-base-100 p-4 hover:border-primary/30 transition-colors"
            >
              <div class="flex items-start justify-between">
                <div>
                  <span class="font-mono font-semibold text-sm text-base-content">{member.name}</span>
                  <p class="text-xs text-base-content/70 mt-0.5">{member.role}</p>
                </div>
                <svg
                  class="h-4 w-4 text-base-content/50 group-hover:text-primary/80 mt-0.5 shrink-0 transition-colors"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path
                    fill-rule="evenodd"
                    d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div :if={member.skills != []} class="flex flex-wrap gap-1 mt-2">
                <span
                  :for={skill_id <- member.skills}
                  class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/60"
                >
                  {skill_id}
                </span>
              </div>
            </a>
          </div>

          <%!-- Add member --%>
          <div :if={@can_edit} class="mt-3">
            <%!-- Default: show "Add team member" button --%>
            <button
              :if={is_nil(@member_mode)}
              phx-click="show_member_picker"
              class="trc-focus inline-flex items-center gap-1.5 rounded px-3 py-2 text-xs font-medium text-base-content/60 hover:text-primary hover:bg-primary/5 transition-colors"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                  clip-rule="evenodd"
                />
              </svg>
              Add team member
            </button>

            <%!-- Step 1: Member picker (pre-built catalog + custom option) --%>
            <div
              :if={@member_mode == :picker}
              role="region"
              aria-label="Add a team member"
              class="rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-4 animate-[fadeIn_150ms_ease-out]"
            >
              <div class="flex items-center justify-between">
                <p class="text-xs font-medium text-base-content/70">Add a team member</p>
                <button
                  phx-click="cancel_member"
                  class="trc-focus text-xs text-base-content/50 hover:text-base-content/60 transition-colors"
                >
                  Cancel
                </button>
              </div>

              <%!-- Custom member option --%>
              <button
                phx-click="custom_member"
                class="trc-focus w-full text-left rounded-lg border border-base-300 bg-base-100 px-3 py-2.5 hover:border-primary/30 transition-colors"
              >
                <div class="flex items-center gap-2.5">
                  <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/60">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-4 w-4"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div>
                    <span class="text-sm font-medium">Create custom agent</span>
                    <p class="text-xs text-base-content/60">Define a new agent from scratch</p>
                  </div>
                </div>
              </button>

              <%!-- Pre-built agents by category --%>
              <%= for category <- @member_catalog do %>
                <div>
                  <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1.5">
                    {category.label}
                  </p>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                    <%= for agent <- category.agents do %>
                      <button
                        phx-click="pick_catalog_member"
                        phx-value-agent-name={agent["name"]}
                        class="trc-focus text-left rounded-md border border-base-300 bg-base-100 px-2.5 py-2 hover:border-primary/30 transition-colors"
                      >
                        <span class="text-xs font-mono font-medium text-base-content truncate">
                          {agent["name"]}
                        </span>
                        <p class="text-[11px] text-base-content/60 mt-0.5 line-clamp-1">
                          {agent["role"]}
                        </p>
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @member_catalog == [] do %>
                <p class="text-xs text-base-content/60 text-center py-2">
                  All available pre-built agents have already been added.
                </p>
              <% end %>
            </div>

            <%!-- Step 2: Member form (for custom or pre-filled from catalog) --%>
            <div
              :if={@member_mode == :form}
              role="region"
              aria-label="Member details form"
              class="rounded-lg border border-base-300 bg-base-200/30 p-3 space-y-2 animate-[fadeIn_150ms_ease-out]"
            >
              <div class="flex flex-col sm:flex-row gap-2">
                <div class="sm:flex-1">
                  <label for="member-name" class="sr-only">Agent name</label>
                  <input
                    id="member-name"
                    type="text"
                    value={@new_member_name}
                    phx-keyup="update_new_member_name"
                    phx-debounce="300"
                    phx-mounted={JS.focus()}
                    maxlength="64"
                    placeholder="agent-name"
                    class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
                  />
                </div>
                <div class="sm:flex-[2]">
                  <label for="member-role" class="sr-only">Role description</label>
                  <input
                    id="member-role"
                    type="text"
                    value={@new_member_role}
                    phx-keyup="update_new_member_role"
                    phx-debounce="300"
                    maxlength="256"
                    placeholder="Role description"
                    class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
                  />
                </div>
              </div>

              <%!-- Catalog agent preview: what's included --%>
              <div
                :if={@new_member_soul != "" || @new_member_skills != []}
                class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-base-content/60"
              >
                <span :if={@new_member_soul != ""} class="inline-flex items-center gap-1">
                  <svg
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
                  Includes instructions
                </span>
                <span :if={@new_member_skills != []} class="inline-flex items-center gap-1">
                  <svg
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
                  {length(@new_member_skills)} skill{if length(@new_member_skills) != 1, do: "s"}:
                </span>
                <span
                  :for={skill_id <- @new_member_skills}
                  class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/60"
                >
                  {skill_id}
                </span>
              </div>

              <div class="flex gap-2">
                <button
                  phx-click="add_member"
                  disabled={@new_member_name == "" || @new_member_role == ""}
                  class={[
                    "trc-focus rounded px-3 py-1.5 text-xs font-semibold transition-all",
                    if(@new_member_name == "" || @new_member_role == "",
                      do: "bg-base-300 text-base-content/50 cursor-not-allowed",
                      else: "bg-primary text-primary-content hover:brightness-110"
                    )
                  ]}
                >
                  Add
                </button>
                <button
                  phx-click="cancel_member"
                  class="trc-focus rounded px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
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
            <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
              Skills <span class="font-mono text-base-content/50 ml-1">{length(@team.skills)}</span>
            </p>
          </div>
          <p class="text-xs text-base-content/60 mb-3">
            Reusable instructions that can be assigned to individual agents. Skills marked
            <span class="font-semibold">all agents</span>
            apply to every agent automatically.
            <a href={~p"/guide#skills"} class="text-primary/80 hover:text-primary transition-colors">
              Learn more
            </a>
          </p>

          <%!-- Existing skills list --%>
          <%= if @team.skills != [] do %>
            <div class="space-y-1.5">
              <%= for skill <- @team.skills do %>
                <div class="group flex items-start justify-between rounded-lg border border-base-300 bg-base-100 px-3 py-2.5">
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-mono font-medium text-base-content">
                        {skill["id"]}
                      </span>
                      <span :if={skill["title"]} class="text-xs text-base-content/60">
                        {skill["title"]}
                      </span>
                      <span
                        :if={skill["alwaysApply"]}
                        class="inline-flex items-center rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary/80"
                      >
                        all agents
                      </span>
                    </div>
                    <p :if={skill["description"]} class="text-xs text-base-content/60 mt-0.5">
                      {skill["description"]}
                    </p>
                  </div>
                  <div
                    :if={@can_edit}
                    class="flex items-center gap-1 ml-2 sm:opacity-0 sm:group-hover:opacity-100 sm:focus-within:opacity-100 transition-opacity"
                  >
                    <button
                      phx-click="edit_skill"
                      phx-value-skill-id={skill["id"]}
                      class="trc-focus rounded p-1 text-base-content/50 hover:text-base-content/70 transition-colors"
                      aria-label="Edit skill"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-3.5 w-3.5"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      >
                        <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                      </svg>
                    </button>
                    <button
                      phx-click="delete_skill"
                      phx-value-skill-id={skill["id"]}
                      data-confirm={"Remove skill \"#{skill["id"]}\"? This will also unassign it from all agents."}
                      class="trc-focus rounded p-1 text-base-content/50 hover:text-error transition-colors"
                      aria-label="Delete skill"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-3.5 w-3.5"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div
              :if={is_nil(@skill_mode)}
              class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center"
            >
              <p class="text-xs text-base-content/60">
                No skills defined. Skills are shared instructions you can assign to specific agents.
              </p>
            </div>
          <% end %>

          <%!-- Add skill button / picker / form --%>
          <div :if={@can_edit} class="mt-3">
            <%!-- Default: show "Add skill" button --%>
            <button
              :if={is_nil(@skill_mode)}
              phx-click="show_skill_picker"
              class="trc-focus inline-flex items-center gap-1.5 rounded px-3 py-2 text-xs font-medium text-base-content/60 hover:text-primary hover:bg-primary/5 transition-colors"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                  clip-rule="evenodd"
                />
              </svg>
              Add skill
            </button>

            <%!-- Step 1: Skill picker (pre-built catalog + custom option) --%>
            <div
              :if={@skill_mode == :picker}
              role="region"
              aria-label="Add a skill"
              class="rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-4 animate-[fadeIn_150ms_ease-out]"
            >
              <div class="flex items-center justify-between">
                <p class="text-xs font-medium text-base-content/70">Add a skill</p>
                <button
                  phx-click="cancel_skill"
                  class="trc-focus text-xs text-base-content/50 hover:text-base-content/60 transition-colors"
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
                  <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/60">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-4 w-4"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div>
                    <span class="text-sm font-medium">Write custom skill</span>
                    <p class="text-xs text-base-content/60">
                      Define your own instructions from scratch
                    </p>
                  </div>
                </div>
              </button>

              <%!-- Pre-built skills by category --%>
              <%= for category <- @skill_catalog do %>
                <div>
                  <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1.5">
                    {category.label}
                  </p>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                    <%= for skill <- category.skills do %>
                      <button
                        phx-click="pick_catalog_skill"
                        phx-value-skill-id={skill["id"]}
                        class="trc-focus text-left rounded-md border border-base-300 bg-base-100 px-2.5 py-2 hover:border-primary/30 transition-colors"
                      >
                        <span class="text-xs font-mono font-medium text-base-content truncate">
                          {skill["id"]}
                        </span>
                        <p
                          :if={skill["description"]}
                          class="text-[11px] text-base-content/60 mt-0.5 line-clamp-1"
                        >
                          {skill["description"]}
                        </p>
                        <p
                          :if={is_nil(skill["description"]) && skill["title"]}
                          class="text-[11px] text-base-content/60 mt-0.5"
                        >
                          {skill["title"]}
                        </p>
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @skill_catalog == [] do %>
                <p class="text-xs text-base-content/60 text-center py-2">
                  All available pre-built skills have already been added.
                </p>
              <% end %>
            </div>

            <%!-- Step 2: Skill form (for custom or pre-filled from catalog) --%>
            <div
              :if={@skill_mode == :form}
              role="region"
              aria-label="Skill details form"
              class="rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-3 animate-[fadeIn_150ms_ease-out]"
            >
              <div class="flex items-center justify-between">
                <p class="text-xs font-medium text-base-content/70">
                  {if @editing_skill, do: "Edit skill", else: "New skill"}
                </p>
                <button
                  phx-click="cancel_skill"
                  class="trc-focus text-xs text-base-content/50 hover:text-base-content/60 transition-colors"
                >
                  Cancel
                </button>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <div>
                  <label for="skill-id" class="block text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1">
                    ID
                  </label>
                  <input
                    id="skill-id"
                    type="text"
                    value={@skill_id}
                    phx-keyup="update_skill_field"
                    phx-value-field="id"
                    phx-debounce="300"
                    maxlength="64"
                    placeholder="code-style"
                    disabled={@editing_skill != nil}
                    class={[
                      "trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors",
                      if(@editing_skill, do: "opacity-50 cursor-not-allowed", else: "")
                    ]}
                  />
                </div>
                <div>
                  <label for="skill-title" class="block text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1">
                    Title <span class="text-base-content/50">(optional)</span>
                  </label>
                  <input
                    id="skill-title"
                    type="text"
                    value={@skill_title}
                    phx-keyup="update_skill_field"
                    phx-value-field="title"
                    phx-debounce="300"
                    maxlength="128"
                    placeholder="Code Style Guide"
                    class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
                  />
                </div>
              </div>

              <div>
                <label for="skill-description" class="block text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1">
                  Description <span class="text-base-content/50">(optional)</span>
                </label>
                <input
                  id="skill-description"
                  type="text"
                  value={@skill_description}
                  phx-keyup="update_skill_field"
                  phx-value-field="description"
                  phx-debounce="300"
                  maxlength="256"
                  placeholder="Enforces consistent code formatting and naming conventions"
                  class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
                />
              </div>

              <div>
                <label for="skill-body" class="block text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-1">
                  Body
                </label>
                <textarea
                  id="skill-body"
                  phx-keyup="update_skill_field"
                  phx-value-field="body"
                  phx-debounce="500"
                  rows="6"
                  placeholder="The instructions for this skill in markdown..."
                  class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-2 text-sm font-mono placeholder:text-base-content/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors resize-y"
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
                  aria-label="Apply to all agents"
                >
                  <span class={[
                    "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(@skill_always_apply, do: "translate-x-4", else: "translate-x-0")
                  ]} />
                </button>
                <span class="text-xs text-base-content/70">Apply to all agents</span>
                <span class="text-[10px] text-base-content/50">
                  (otherwise, assign per-agent on their detail page)
                </span>
              </div>

              <div class="flex gap-2 pt-1">
                <button
                  phx-click="save_skill"
                  disabled={@skill_id == "" || @skill_body == ""}
                  class={[
                    "trc-focus rounded px-3 py-1.5 text-xs font-semibold transition-all",
                    if(@skill_id == "" || @skill_body == "",
                      do: "bg-base-300 text-base-content/50 cursor-not-allowed",
                      else: "bg-primary text-primary-content hover:brightness-110"
                    )
                  ]}
                >
                  {if @editing_skill, do: "Update skill", else: "Add skill"}
                </button>
                <button
                  phx-click="cancel_skill"
                  class="trc-focus rounded px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </section>

        <%!-- Knowledge --%>
        <section>
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            Knowledge
          </p>
          <div
            :if={@team.knowledge && @team.knowledge != ""}
            class="rounded-lg border border-base-300 bg-base-100 px-4 py-3"
          >
            <pre class="text-xs font-mono text-base-content/70 whitespace-pre-wrap break-words"><%= @team.knowledge %></pre>
          </div>
          <div
            :if={is_nil(@team.knowledge) || @team.knowledge == ""}
            class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center"
          >
            <p class="text-xs text-base-content/60">
              No knowledge yet. Knowledge is managed via the CLI.
              <a
                href={~p"/guide#knowledge"}
                class="text-primary/80 hover:text-primary transition-colors"
              >
                Learn more
              </a>
            </p>
          </div>
        </section>

        <%!-- Participants (owner only) --%>
        <section :if={@can_edit && @participants != []}>
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            Participants
          </p>
          <div class="flex flex-wrap gap-1.5">
            <span
              :for={p <- @participants}
              class={[
                "inline-flex items-center rounded px-2 py-1 text-xs font-mono",
                if(@current_user && p == Teamrc.PII.email_hash(@current_user.email),
                  do: "bg-primary/10 text-primary",
                  else: "bg-base-200/60 text-base-content/60"
                )
              ]}
            >
              {if @current_user && p == Teamrc.PII.email_hash(@current_user.email), do: "you", else: String.slice(p, 0, 8) <> "..."}
            </span>
          </div>
        </section>

        <%!-- Invites (owner only) --%>
        <section :if={@can_edit}>
          <div class="flex items-center justify-between mb-3">
            <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
              Invites <span class="font-mono text-base-content/50 ml-1">{length(@invites)}</span>
            </p>
            <button
              phx-click="generate_invite"
              class="trc-focus inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                  clip-rule="evenodd"
                />
              </svg>
              Generate invite
            </button>
          </div>
          <p class="text-xs text-base-content/60 mb-3">
            Invite codes grant <span class="text-amber-500/80 font-medium">full edit access</span> to this team: members, skills, knowledge, and settings. Only share with collaborators you trust.
          </p>

          <%!-- Newly generated invite --%>
          <div
            :if={@generated_invite}
            class="rounded-lg border border-primary/30 bg-primary/5 p-4 mb-4 animate-[fadeIn_150ms_ease-out]"
          >
            <div class="flex items-center justify-between mb-2">
              <p class="text-xs font-medium text-primary">New invite generated</p>
              <button
                phx-click="dismiss_generated_invite"
                class="trc-focus text-xs text-base-content/50 hover:text-base-content/60 transition-colors"
              >
                Dismiss
              </button>
            </div>
            <div class="terminal-block rounded-md overflow-hidden">
              <div class="flex items-center justify-between px-3 py-2">
                <code class="text-emerald-400 text-sm font-mono">
                  npx @teamrc/cli join {@generated_invite.code}
                </code>
                <button
                  phx-click={
                    JS.dispatch("trc:copy",
                      detail: %{text: "npx @teamrc/cli join #{@generated_invite.code}"}
                    )
                  }
                  class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
                  aria-label="Copy invite command"
                >
                  Copy
                </button>
              </div>
            </div>
            <p class="text-xs text-base-content/60 mt-2">
              Invite code expires in {time_remaining(@generated_invite.expires_at)}. Anyone with this code can edit this team.
            </p>
          </div>

          <%!-- Existing invites --%>
          <div :if={@invites != []} class="space-y-2">
            <div
              :for={invite <- @invites}
              class="rounded-md border border-base-300 bg-base-100 px-3 py-2"
            >
              <div class="terminal-block rounded-md overflow-hidden mb-2">
                <div class="flex items-center justify-between px-3 py-2">
                  <code class="text-emerald-400 text-xs font-mono">
                    npx @teamrc/cli join {invite.code}
                  </code>
                  <button
                    phx-click={
                      JS.dispatch("trc:copy",
                        detail: %{text: "npx @teamrc/cli join #{invite.code}"}
                      )
                    }
                    class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
                    aria-label="Copy invite command"
                  >
                    Copy
                  </button>
                </div>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-[10px] text-base-content/50">
                  expires in {time_remaining(invite.expires_at)}
                </span>
                <button
                  phx-click="revoke_invite"
                  phx-value-id={invite.id}
                  data-confirm="Revoke this invite? It will no longer be usable."
                  class="trc-focus text-[10px] text-red-500/60 hover:text-red-500 transition-colors"
                >
                  Revoke
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@invites == [] && is_nil(@generated_invite)}
            class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center"
          >
            <p class="text-xs text-base-content/60">No active invites.</p>
          </div>

          <%!-- Clone token display for owners --%>
          <div
            :if={@team.visibility == "public" && @clone_token}
            class="mt-4 pt-4 border-t border-base-300"
          >
            <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-2">
              Clone Token
            </p>
            <p class="text-xs text-base-content/60 mb-2">
              Anyone with this token can copy the team config and pull updates (read-only, no edit access).
            </p>
            <div class="terminal-block rounded-lg overflow-hidden">
              <div class="px-3 py-2">
                <code class="text-emerald-400 text-xs font-mono">
                  npx @teamrc/cli clone {@clone_token}
                </code>
              </div>
            </div>
          </div>
        </section>

        <%!-- Claim ownership (logged-in participant who is not the owner, team has no owner) --%>
        <section
          :if={@current_user && @access_level == :participant && @team.owner_user_id == nil}
          class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
        >
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-base-content">Claim ownership</p>
              <p class="text-xs text-base-content/60 mt-0.5">
                This team has no owner. If you have the claim secret (shown when the team was created via the CLI), you can become the owner.
              </p>
            </div>
            <button
              :if={!@show_claim_form}
              phx-click="show_claim_form"
              class="trc-focus shrink-0 ml-4 rounded-md bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content hover:brightness-110 transition-all"
            >
              Claim
            </button>
          </div>
          <div :if={@show_claim_form} class="space-y-2">
            <label for="claim-secret" class="sr-only">Claim secret</label>
            <input
              id="claim-secret"
              type="text"
              value={@claim_secret_input}
              phx-keyup="update_claim_secret"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              placeholder="trc_ocs_..."
              autocomplete="off"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm font-mono placeholder:text-base-content/40 focus:border-primary/50 focus:ring-1 focus:ring-primary/50 transition-colors"
            />
            <div class="flex items-center gap-2">
              <button
                phx-click="submit_claim"
                class="trc-focus rounded-md bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content hover:brightness-110 transition-all"
              >
                Verify & claim
              </button>
              <button
                phx-click="cancel_claim"
                class="trc-focus rounded-md px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/70 transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </section>

        <%!-- Delete team (authenticated owner only, not creator sessions) --%>
        <section :if={@is_owner && !@is_creator_session} class="pt-4 border-t border-error/20">
          <p class="text-xs font-medium text-error/70 uppercase tracking-wider mb-2">
            Danger zone
          </p>
          <div class="rounded-lg border border-error/20 bg-error/5 p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-base-content">Delete this team</p>
                <p class="text-xs text-base-content/60 mt-0.5">
                  Permanently removes the team, all members, skills, and invites from the relay. Connected machines will need to re-initialize.
                </p>
              </div>
              <button
                phx-click="delete_team"
                data-confirm={"Permanently delete \"#{@team.name}\"? This cannot be undone."}
                class="trc-focus shrink-0 ml-4 rounded-md border border-error/30 bg-error/10 px-3 py-1.5 text-xs font-semibold text-error hover:bg-error/20 transition-colors"
              >
                Delete team
              </button>
            </div>
          </div>
        </section>
      </div>

      <%!-- Share confirmation modal --%>
      <div
        :if={@show_share_modal}
        id="share-modal"
        class="fixed inset-0 z-50 flex items-center justify-center"
        role="dialog"
        aria-modal="true"
        aria-labelledby="share-modal-title"
        phx-window-keydown="close_share_modal"
        phx-key="Escape"
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-zinc-900/50"
          phx-click="close_share_modal"
          aria-hidden="true"
        >
        </div>

        <%!-- Modal card --%>
        <div class="relative mx-4 w-full max-w-md rounded-lg border border-base-300 bg-base-100 p-6 shadow-lg animate-[fadeIn_150ms_ease-out]">
          <h2 id="share-modal-title" class="text-base font-semibold text-base-content">
            Share your team publicly?
          </h2>
          <p class="mt-3 text-sm text-base-content/70 leading-relaxed">
            By sharing, your team definition becomes public and anyone with the link can clone it. Your knowledge files will not be shared.
          </p>
          <p class="mt-2 text-sm text-base-content/70">
            You can make it private again at any time.
          </p>
          <div class="mt-6 flex items-center justify-end gap-3">
            <button
              phx-click="close_share_modal"
              class="trc-focus rounded-md px-4 py-2 text-sm font-medium text-base-content/60 hover:text-base-content/80 hover:bg-base-200/60 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="confirm_share"
              class="trc-focus rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
            >
              Share publicly
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
