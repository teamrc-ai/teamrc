defmodule Teamrc.Teams do
  @moduledoc "Context module for team operations. No GenServer — all queries run in the caller's process."

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, Member, Invite, TokenTeam}

  @invite_ttl_hours 24

  # --- Public API ---

  @doc "Create or update a team for a token."
  def put_team(token, team_attrs, team_id \\ nil) do
    team_data = normalize_team(team_attrs)

    case resolve_team_id(token, team_id) do
      nil ->
        case create_team_in_db(team_data) do
          {:ok, team} ->
            upsert_token_team(token, team.id)
            {:ok, team_to_map(team)}

          {:error, reason} ->
            {:error, reason}
        end

      resolved_id ->
        case update_team_in_db(resolved_id, team_data) do
          {:ok, team} -> {:ok, team_to_map(team)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Create a team with a random invite code. Returns {:ok, invite_code, team_id}."
  def create_team_with_invite(team_attrs) do
    team_data = normalize_team(team_attrs)
    invite_code = generate_invite_code()
    expires_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(@invite_ttl_hours * 3600)

    case create_team_in_db(team_data) do
      {:ok, team} ->
        case %Invite{}
             |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team.id})
             |> Repo.insert() do
          {:ok, _invite} ->
            {:ok, invite_code, team.id}

          {:error, _changeset} ->
            {:error, :invite_creation_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Join a team by invite code. Returns {:ok, team_map} or :error."
  def join_by_invite(invite_code, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      from(i in Invite,
        where: i.code == ^invite_code and i.expires_at > ^now,
        preload: [team: :members]
      )
      |> Repo.one()

    case result do
      nil ->
        :error

      %Invite{team: team} ->
        upsert_token_team(token, team.id)
        {:ok, team_to_map(team)}
    end
  end

  @doc "Get a team by token. Returns {:ok, team_map} or :error."
  def get_team(token, team_id \\ nil) do
    case resolve_team_id(token, team_id) do
      nil ->
        :error

      resolved_id ->
        team = Repo.get(Team, resolved_id) |> Repo.preload(:members)

        if team do
          {:ok, team_to_map(team)}
        else
          :error
        end
    end
  end

  @doc "Get all teams for a token. Returns {:ok, [team_map]} or :error."
  def get_teams(token) do
    team_ids =
      from(tt in TokenTeam, where: tt.token == ^token, select: tt.team_id)
      |> Repo.all()

    case team_ids do
      [] ->
        :error

      ids ->
        teams =
          from(t in Team, where: t.id in ^ids, preload: [:members])
          |> Repo.all()
          |> Enum.map(&team_to_map/1)

        {:ok, teams}
    end
  end

  @doc "Preview a team by invite code without joining. Returns {:ok, team_map} or :error."
  def preview_by_invite(invite_code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      from(i in Invite,
        where: i.code == ^invite_code and i.expires_at > ^now,
        preload: [team: :members]
      )
      |> Repo.one()

    case result do
      nil -> :error
      %Invite{team: team} -> {:ok, team_to_map(team)}
    end
  end

  @doc "Create a new invite code for a team the token belongs to. Returns {:ok, code, expires_at} or :error."
  def create_invite(token, ttl_hours, team_id \\ nil) do
    case resolve_team_id(token, team_id) do
      nil ->
        :error

      resolved_id ->
        invite_code = generate_invite_code()
        expires_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(ttl_hours * 3600)

        case %Invite{}
             |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: resolved_id})
             |> Repo.insert() do
          {:ok, _invite} ->
            {:ok, invite_code, expires_at}

          {:error, _changeset} ->
            {:error, :invite_creation_failed}
        end
    end
  end

  @doc "Preview a team by clone token. Returns {:ok, team_map} or :error."
  def preview_by_clone_token(clone_token) do
    result =
      from(t in Team,
        where: t.clone_token == ^clone_token and t.visibility == "public",
        preload: [:members]
      )
      |> Repo.one()

    case result do
      nil -> :error
      %Team{} = team ->
        map = team_to_map(team) |> Map.delete("knowledge")
        {:ok, map}
    end
  end

  @doc "Set team visibility and manage clone token. Returns {:ok, team} or {:error, reason}."
  def set_visibility(team_id, visibility) when visibility in ["public", "private"] do
    case Repo.get(Team, team_id) do
      nil ->
        {:error, :not_found}

      team ->
        attrs =
          case visibility do
            "public" ->
              clone_token = team.clone_token || generate_clone_token()
              %{visibility: "public", clone_token: clone_token}

            "private" ->
              %{visibility: "private", clone_token: nil}
          end

        team |> Team.changeset(attrs) |> Repo.update()
    end
  end

  def set_visibility(_team_id, _visibility), do: {:error, :invalid_visibility}

  # --- Private helpers ---

  defp resolve_team_id(token, nil) do
    from(tt in TokenTeam, where: tt.token == ^token, select: tt.team_id, limit: 1)
    |> Repo.one()
  end

  defp resolve_team_id(token, team_id) do
    from(tt in TokenTeam,
      where: tt.token == ^token and tt.team_id == ^team_id,
      select: tt.team_id
    )
    |> Repo.one()
  end

  defp upsert_token_team(token, team_id) do
    %TokenTeam{}
    |> TokenTeam.changeset(%{token: token, team_id: team_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:token, :team_id])
  end

  defp generate_invite_code do
    "trc_inv_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp generate_clone_token do
    "trc_cl_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp create_team_in_db(team_data) do
    Repo.transaction(fn ->
      case %Team{}
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms, knowledge: team_data.knowledge})
           |> Repo.insert() do
        {:ok, team} ->
          Enum.each(team_data.members, fn m ->
            case %Member{team_id: team.id}
                 |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
                 |> Repo.insert() do
              {:ok, _member} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

          Repo.preload(team, :members)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp update_team_in_db(team_id, team_data) do
    Repo.transaction(fn ->
      team = Repo.get!(Team, team_id)

      case team
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms, knowledge: team_data.knowledge})
           |> Repo.update() do
        {:ok, team} ->
          # Replace members atomically within the transaction
          from(m in Member, where: m.team_id == ^team_id) |> Repo.delete_all()

          Enum.each(team_data.members, fn m ->
            case %Member{team_id: team_id}
                 |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
                 |> Repo.insert() do
              {:ok, _member} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

          Repo.preload(team, :members, force: true)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp normalize_team(attrs) when is_map(attrs) do
    members =
      (attrs["members"] || attrs[:members] || [])
      |> Enum.map(fn m ->
        %{
          name: m["name"] || m[:name] || "",
          role: m["role"] || m[:role] || "",
          soul: m["soul"] || m[:soul],
          skills: m["skills"] || m[:skills] || []
        }
      end)

    skills =
      (attrs["skills"] || attrs[:skills] || [])
      |> Enum.map(fn s ->
        %{
          "id" => s["id"] || s[:id] || "",
          "title" => s["title"] || s[:title],
          "description" => s["description"] || s[:description],
          "alwaysApply" => s["alwaysApply"] || s[:alwaysApply],
          "globs" => s["globs"] || s[:globs],
          "userInvocable" => s["userInvocable"] || s[:userInvocable],
          "body" => s["body"] || s[:body]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    platforms = attrs["platforms"] || attrs[:platforms] || []
    knowledge = attrs["knowledge"] || attrs[:knowledge]

    %{name: attrs["name"] || attrs[:name] || "", members: members, skills: skills, platforms: platforms, knowledge: knowledge}
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp team_to_map(%Team{} = team) do
    %{
      "id" => team.id,
      "name" => team.name,
      "updated_at" => team.updated_at && DateTime.to_iso8601(team.updated_at),
      "knowledge" => team.knowledge,
      "members" =>
        Enum.map(team.members, fn m ->
          %{"name" => m.name, "role" => m.role}
          |> put_if_present("soul", m.soul)
          |> put_if_present("skills", m.skills)
        end)
    }
    |> put_if_present("skills", team.skills)
    |> put_if_present("platforms", team.platforms)
  end
end
