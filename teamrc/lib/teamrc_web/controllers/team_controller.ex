defmodule TeamrcWeb.TeamController do
  use TeamrcWeb, :controller

  alias Teamrc.{Catalog, Teams}

  @doc """
  POST /teams/create-web — creates a team from a template, writes
  a creator session token (for non-logged-in users) and redirects
  to the team detail page.
  """
  def create(conn, %{"template" => key}) do
    template = Catalog.resolve_team(key)

    if is_nil(template) do
      conn
      |> put_flash(:error, "Unknown template.")
      |> redirect(to: ~p"/new")
    else
      team_payload = build_team_payload(template)
      current_user = conn.assigns[:current_scope] && conn.assigns.current_scope.user
      opts = if current_user, do: [owner_user_id: current_user.id], else: []

      case Teams.create_team_with_invite(team_payload, opts) do
        {:ok, invite_code, team_id, creator_token} ->
          conn = put_flash(conn, :invite_code, invite_code)

          # Store creator token in session so the creator can edit
          # their team in the browser without logging in.
          conn =
            if creator_token do
              creator_sessions = get_session(conn, "creator_sessions") || %{}
              put_session(conn, "creator_sessions", Map.put(creator_sessions, team_id, creator_token))
            else
              conn
            end

          redirect(conn, to: "/teams/#{team_id}")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to create team.")
          |> redirect(to: ~p"/new")
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Missing template.")
    |> redirect(to: ~p"/new")
  end

  defp build_team_payload(template) do
    skills_clean =
      template.skills
      |> Enum.filter(&(&1.id != ""))
      |> Enum.map(fn s ->
        %{id: s.id}
        |> put_if(s[:title], :title)
        |> put_if(s[:description], :description)
        |> put_if(s[:alwaysApply], :alwaysApply)
        |> put_if(s[:globs], :globs)
        |> put_if(s[:userInvocable], :userInvocable)
        |> put_if(s[:body], :body)
      end)

    skill_ids = MapSet.new(skills_clean, & &1.id)

    %{
      name: template.team_name,
      platforms: template.default_platforms,
      members:
        template.members
        |> Enum.filter(&(&1.name != ""))
        |> Enum.map(fn m ->
          member = %{name: m.name, role: m.role}
          member = if m[:soul] && m.soul != "", do: Map.put(member, :soul, m.soul), else: member
          member_skills = (m[:skills] || []) |> Enum.filter(&MapSet.member?(skill_ids, &1))
          if member_skills != [], do: Map.put(member, :skills, member_skills), else: member
        end),
      skills: skills_clean
    }
  end

  defp put_if(map, nil, _key), do: map
  defp put_if(map, false, _key), do: map
  defp put_if(map, "", _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)
end
