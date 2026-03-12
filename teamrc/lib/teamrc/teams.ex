defmodule Teamrc.Teams do
  @moduledoc "Context module for team operations. No GenServer — all queries run in the caller's process."

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, Member, Invite, TokenTeam, AccountToken}
  alias Teamrc.ContentHash

  @invite_ttl_hours 24

  # --- Public API ---

  @doc "Create or update a team for a token."
  def put_team(token, team_attrs, team_id \\ nil) do
    team_data = normalize_team(team_attrs)
    base_hash = team_attrs["base_hash"] || team_attrs[:base_hash]

    case resolve_team_id(token, team_id) do
      nil ->
        case create_team_in_db(team_data, token) do
          {:ok, team} ->
            upsert_token_team(token, team.id)
            # Include claim secret only on initial creation (shown once to creator)
            map = team_to_map(team)
              |> put_if_present("owner_claim_secret", team.owner_claim_secret)
            {:ok, map}

          {:error, reason} ->
            {:error, reason}
        end

      resolved_id ->
        case update_team_in_db(resolved_id, team_data, base_hash) do
          {:ok, team} -> {:ok, team_to_map(team)}
          {:error, :conflict, hashes} -> {:error, :conflict, hashes}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Create a team with a random invite code. Returns {:ok, invite_code, team_id}."
  def create_team_with_invite(team_attrs, opts \\ []) do
    team_data = normalize_team(team_attrs)
    invite_code = generate_invite_code()
    expires_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(@invite_ttl_hours * 3600)
    owner_account_id = Keyword.get(opts, :owner_account_id)

    Repo.transaction(fn ->
      case create_team_in_db_inner(team_data, nil, owner_account_id) do
        {:ok, team} ->
          case %Invite{}
               |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team.id})
               |> Repo.insert() do
            {:ok, _invite} ->
              {invite_code, team.id}

            {:error, changeset} ->
              Repo.rollback({:invite_creation_failed, changeset})
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {invite_code, team_id}} -> {:ok, invite_code, team_id}
      {:error, _reason} -> {:error, :creation_failed}
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
      %Invite{team: team} ->
        # Redact knowledge and member souls from preview (join required for full content)
        map = team_to_map(team)
          |> Map.delete("knowledge")
          |> Map.update("members", [], fn members ->
            Enum.map(members, &Map.delete(&1, "soul"))
          end)
        {:ok, map}
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

  @doc "Set team visibility. Requires the token to belong to the team's owner account."
  def set_visibility(token, team_id, visibility) when visibility in ["public", "private"] do
    case resolve_team_id(token, team_id) do
      nil ->
        {:error, :not_authorized}

      resolved_team_id ->
        if Teamrc.Accounts.is_team_owner?(token, resolved_team_id) do
          do_set_visibility(resolved_team_id, visibility)
        else
          {:error, :not_owner}
        end
    end
  end

  def set_visibility(_token, _team_id, _visibility), do: {:error, :invalid_visibility}

  defp do_set_visibility(team_id, visibility) do
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
              %{visibility: "private"}
          end

        team |> Team.changeset(attrs) |> Repo.update()
    end
  end

  @doc "Claim ownership of a team using the claim secret. Requires the token to have a linked account."
  def claim_ownership(token, claim_secret) do
    # Resolve the team by the claim secret
    team =
      from(t in Team, where: t.owner_claim_secret == ^claim_secret and is_nil(t.owner_account_id))
      |> Repo.one()

    case team do
      nil ->
        {:error, :invalid_secret}

      %Team{} = team ->
        # Verify the token has a linked account
        account_id = resolve_owner_from_token(token)

        if is_nil(account_id) do
          {:error, :no_account}
        else
          # Verify the token belongs to this team
          is_member =
            from(tt in TokenTeam, where: tt.token == ^token and tt.team_id == ^team.id, select: tt.id, limit: 1)
            |> Repo.one()

          if is_nil(is_member) do
            {:error, :not_member}
          else
            # Atomic claim — only succeeds if still unclaimed
            {count, _} =
              from(t in Team, where: t.id == ^team.id and is_nil(t.owner_account_id))
              |> Repo.update_all(set: [owner_account_id: account_id, owner_claim_secret: nil])

            if count == 1 do
              {:ok, :claimed}
            else
              {:error, :already_claimed}
            end
          end
        end
    end
  end

  @doc "Erase all token_teams rows for a given token. Returns {:ok, count} with the number of rows deleted."
  def erase_token(token) do
    {count, _} =
      from(tt in TokenTeam, where: tt.token == ^token)
      |> Repo.delete_all()

    {:ok, count}
  end

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

  defp generate_claim_secret do
    "trc_ocs_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp create_team_in_db(team_data, token) do
    Repo.transaction(fn ->
      case create_team_in_db_inner(team_data, token) do
        {:ok, team} -> team
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_team_in_db_inner(team_data, token, owner_account_id \\ nil) do
    # If a token is provided and no explicit owner, check if the token already has a linked account
    resolved_owner =
      owner_account_id || resolve_owner_from_token(token)

    # Generate a claim secret only when there is no owner yet (CLI flow).
    # Web wizard sets owner_account_id directly, so no secret needed.
    claim_secret = if is_nil(resolved_owner), do: generate_claim_secret()

    team_attrs =
      %{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms, knowledge: team_data.knowledge}
      |> put_non_nil(:owner_claim_secret, claim_secret)
      |> put_non_nil(:owner_account_id, resolved_owner)

    case %Team{}
         |> Team.changeset(team_attrs)
         |> Repo.insert() do
      {:ok, team} ->
        Enum.each(team_data.members, fn m ->
          %Member{team_id: team.id}
          |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
          |> Repo.insert!()
        end)

        team = Repo.preload(team, :members)
        hashes = ContentHash.compute_team_hashes(team)

        {:ok, team} =
          team
          |> Team.changeset(%{
            members_hash: hashes.members_hash,
            skills_hash: hashes.skills_hash,
            knowledge_hash: hashes.knowledge_hash
          })
          |> Repo.update()

        {:ok, Repo.preload(team, :members)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp update_team_in_db(team_id, team_data, base_hash) do
    result =
      Repo.transaction(fn ->
        team = Repo.get(Team, team_id)

        if is_nil(team) do
          Repo.rollback(:not_found)
        end

        team = Repo.preload(team, :members)

        # Resolve effective team_data (may merge knowledge on conflict)
        effective_team_data =
          if base_hash do
            current_hashes = ContentHash.compute_team_hashes(team)

            if current_hashes.hash != base_hash do
              # Check if only knowledge differs — attempt server-side merge
              incoming_members_hash = ContentHash.compute_members_hash(
                Enum.map(team_data.members, fn m ->
                  %{"name" => m.name, "role" => m[:role], "soul" => m[:soul], "skills" => m.skills}
                end)
              )
              incoming_skills_hash = ContentHash.compute_skills_hash(team_data.skills)

              if incoming_members_hash == current_hashes.members_hash and
                 incoming_skills_hash == current_hashes.skills_hash and
                 team_data.knowledge do
                # Only knowledge differs — merge server-side inside this transaction
                merged = ContentHash.merge_knowledge(team.knowledge, team_data.knowledge)
                if is_binary(merged) and byte_size(merged) > 100_000 do
                  Repo.rollback({:conflict, current_hashes})
                else
                  %{team_data | knowledge: merged}
                end
              else
                Repo.rollback({:conflict, current_hashes})
              end
            else
              team_data
            end
          else
            team_data
          end

        do_update_team(team, team_id, effective_team_data)
      end)

    case result do
      {:ok, team} ->
        {:ok, team}

      {:error, {:conflict, hashes}} ->
        {:error, :conflict, hashes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_update_team(team, team_id, team_data) do
    # Knowledge is append-only: always merge incoming with existing to prevent data loss.
    # Omitting knowledge (nil) preserves the existing server value.
    attrs = %{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms}
    attrs = if team_data.knowledge do
      merged = ContentHash.merge_knowledge(team.knowledge, team_data.knowledge)
      Map.put(attrs, :knowledge, merged)
    else
      attrs
    end

    case team
         |> Team.changeset(attrs)
         |> Repo.update() do
      {:ok, team} ->
        # Only replace members if the incoming set differs from what's in DB
        existing = Enum.map(team.members, fn m ->
          %{name: m.name, role: m.role, soul: m.soul, skills: m.skills || []}
        end) |> Enum.sort_by(& &1.name)

        incoming = Enum.map(team_data.members, fn m ->
          %{name: m.name, role: m[:role], soul: m[:soul], skills: m.skills || []}
        end) |> Enum.sort_by(& &1.name)

        if existing != incoming do
          from(m in Member, where: m.team_id == ^team_id) |> Repo.delete_all()

          Enum.each(team_data.members, fn m ->
            case %Member{team_id: team_id}
                 |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
                 |> Repo.insert() do
              {:ok, _member} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)
        end

        team = Repo.preload(team, :members, force: true)

        # Compute and stamp hashes after update
        hashes = ContentHash.compute_team_hashes(team)

        {:ok, team} =
          team
          |> Team.changeset(%{
            members_hash: hashes.members_hash,
            skills_hash: hashes.skills_hash,
            knowledge_hash: hashes.knowledge_hash
          })
          |> Repo.update()

        Repo.preload(team, :members, force: true)

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
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
          "alwaysApply" => get_bool_field(s, :alwaysApply, "alwaysApply"),
          "globs" => s["globs"] || s[:globs],
          "userInvocable" => get_bool_field(s, :userInvocable, "userInvocable"),
          "body" => s["body"] || s[:body]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    platforms = attrs["platforms"] || attrs[:platforms] || []
    knowledge = attrs["knowledge"] || attrs[:knowledge]

    %{name: attrs["name"] || attrs[:name] || "", members: members, skills: skills, platforms: platforms, knowledge: knowledge}
  end

  defp resolve_owner_from_token(nil), do: nil

  defp resolve_owner_from_token(token) do
    from(at in AccountToken,
      where: at.token == ^token and is_nil(at.revoked_at),
      select: at.account_id,
      limit: 1
    )
    |> Repo.one()
  end

  # Get a boolean field from either atom-keyed or string-keyed map.
  # Uses explicit nil check instead of || to handle false values correctly.
  defp get_bool_field(map, atom_key, string_key) do
    case Map.get(map, atom_key) do
      nil -> Map.get(map, string_key)
      value -> value
    end
  end

  defp put_non_nil(map, _key, nil), do: map
  defp put_non_nil(map, key, val), do: Map.put(map, key, val)

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  @doc "Get just the hashes for a team. Reads stored hash columns — no member preload needed."
  def get_team_hashes(token, team_id \\ nil) do
    case resolve_team_id(token, team_id) do
      nil ->
        :error

      resolved_id ->
        result =
          from(t in Team,
            where: t.id == ^resolved_id,
            select: %{
              members_hash: t.members_hash,
              skills_hash: t.skills_hash,
              knowledge_hash: t.knowledge_hash
            }
          )
          |> Repo.one()

        case result do
          nil ->
            :error

          %{members_hash: mh, skills_hash: sh, knowledge_hash: kh}
          when is_binary(mh) and is_binary(sh) and is_binary(kh) ->
            full_hash = ContentHash.compute_full_hash(mh, sh, kh)
            {:ok, %{"hash" => full_hash, "members_hash" => mh, "skills_hash" => sh, "knowledge_hash" => kh}}

          _ ->
            # Fallback: hashes not yet stamped, compute from full team
            team = Repo.get(Team, resolved_id) |> Repo.preload(:members)
            if team do
              hashes = ContentHash.compute_team_hashes(team)
              {:ok, %{"hash" => hashes.hash, "members_hash" => hashes.members_hash, "skills_hash" => hashes.skills_hash, "knowledge_hash" => hashes.knowledge_hash}}
            else
              :error
            end
        end
    end
  end

  defp team_to_map(%Team{} = team) do
    hashes = ContentHash.compute_team_hashes(team)

    %{
      "id" => team.id,
      "name" => team.name,
      "knowledge" => team.knowledge,
      "hash" => hashes.hash,
      "members_hash" => hashes.members_hash,
      "skills_hash" => hashes.skills_hash,
      "knowledge_hash" => hashes.knowledge_hash,
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
