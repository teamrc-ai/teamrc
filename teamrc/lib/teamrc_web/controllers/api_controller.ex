defmodule TeamrcWeb.ApiController do
  use TeamrcWeb, :controller
  use TeamrcWeb.Plugs.ApiErrorHandler

  require Logger
  alias Teamrc.Teams

  # Input validation limits
  @max_team_name_length 64
  @max_members 20
  @max_skills 50
  @max_skill_body_bytes 10_000  # 10KB per skill body
  @id_re ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/

  def create_team(conn, %{"token" => token, "team" => team} = params) do
    with :ok <- validate_team(team) do
      sanitized = sanitize_team(team)
      # Preserve base_hash if it's a valid SHA-256 hex string (64 lowercase hex chars)
      base_hash = params["base_hash"]
      sanitized = if is_binary(base_hash) and Regex.match?(~r/^[0-9a-f]{64}$/, base_hash),
        do: Map.put(sanitized, "base_hash", base_hash),
        else: sanitized
      team_id = params["team_id"]

      case Teams.put_team(token, sanitized, team_id) do
        {:ok, team_data} ->
          conn
          |> put_status(:created)
          |> json(%{team: team_data})

        {:error, :conflict, hashes} ->
          conn
          |> put_status(:conflict)
          |> json(%{
            error: "conflict",
            server_hash: hashes.hash
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: reason})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  def head_team(conn, %{"token" => token} = params) do
    team_id = params["team_id"]

    case Teams.get_team_hashes(token, team_id) do
      {:ok, hashes} ->
        json(conn, hashes)

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  def get_team(conn, %{"token" => token} = params) do
    case Teams.get_team(token, params["team_id"]) do
      {:ok, team} ->
        json(conn, %{team: team})

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  def get_teams(conn, %{"token" => token}) do
    case Teams.get_teams(token) do
      {:ok, teams} ->
        json(conn, %{teams: teams})

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  def join_team(conn, %{"invite_code" => invite_code, "token" => token}) do
    case Teams.join_by_invite(invite_code, token) do
      {:ok, team} ->
        json(conn, %{team: team, token: token})

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "invalid_invite"})
    end
  end

  def preview_team(conn, %{"invite_code" => invite_code}) do
    case Teams.preview_by_invite(invite_code) do
      {:ok, team} -> json(conn, %{team: team})
      :error -> conn |> put_status(:not_found) |> json(%{error: "invalid_invite"})
    end
  end

  def create_invite(conn, params) do
    token = conn.assigns[:verified_token]
    ttl = min(safe_integer(params["ttl_hours"], 24), 168)
    team_id = params["team_id"]

    case Teams.create_invite(token, ttl, team_id) do
      {:ok, code, expires_at} ->
        json(conn, %{invite_code: code, expires_at: DateTime.to_iso8601(expires_at)})

      :error ->
        conn |> put_status(:forbidden) |> json(%{error: "not a team member"})
    end
  end

  def clone_team(conn, %{"clone_token" => clone_token}) do
    case Teams.preview_by_clone_token(clone_token) do
      {:ok, team} -> json(conn, %{team: team})
      :error -> conn |> put_status(:not_found) |> json(%{error: "invalid_clone_token"})
    end
  end

  def set_visibility(conn, %{"visibility" => visibility} = params) do
    token = conn.assigns[:verified_token]
    team_id = params["team_id"]

    case Teams.set_visibility(token, team_id, visibility) do
      {:ok, team} ->
        json(conn, %{
          visibility: team.visibility,
          clone_token: team.clone_token
        })

      {:error, :not_authorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "not a team member"})

      {:error, :not_owner} ->
        conn |> put_status(:forbidden) |> json(%{error: "only the team owner can change visibility. Link your account with `teamrc login`."})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :invalid_visibility} ->
        conn |> put_status(:bad_request) |> json(%{error: "visibility must be 'public' or 'private'"})
    end
  end

  def claim_ownership(conn, %{"claim_secret" => claim_secret}) do
    token = conn.assigns[:verified_token]

    case Teams.claim_ownership(token, claim_secret) do
      {:ok, :claimed} ->
        json(conn, %{status: "claimed"})

      {:error, :invalid_secret} ->
        conn |> put_status(:not_found) |> json(%{error: "invalid or already-claimed ownership token"})

      {:error, :no_account} ->
        conn |> put_status(:forbidden) |> json(%{error: "link your account first with `teamrc login`"})

      {:error, :already_claimed} ->
        conn |> put_status(:conflict) |> json(%{error: "team already has an owner"})
    end
  end

  def erase_token(conn, params) do
    token = conn.assigns[:verified_token]
    team_id = params["team_id"]

    {:ok, count} = Teams.erase_token(token, team_id)

    json(conn, %{status: "disconnected", teams_removed: count})
  end

  # --- Input Validation ---

  @valid_platforms ~w(claude-code cursor codex gemini openclaw claude-desktop)

  defp validate_team(team) do
    with :ok <- validate_team_name(team["name"]),
         :ok <- validate_members(team["members"]),
         :ok <- validate_skills(team["skills"]),
         :ok <- validate_knowledge(team["knowledge"]),
         :ok <- validate_platforms(team["platforms"]) do
      :ok
    end
  end

  defp validate_team_name(nil), do: :ok
  defp validate_team_name(name) when is_binary(name) do
    name = String.trim(name)
    cond do
      name == "" ->
        {:error, "team name must not be empty"}
      byte_size(name) > @max_team_name_length ->
        {:error, "team name must be #{@max_team_name_length} characters or fewer"}
      not Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9 _-]*$/, name) ->
        {:error, "team name must be alphanumeric (hyphens, underscores, and spaces allowed)"}
      true ->
        :ok
    end
  end
  defp validate_team_name(_), do: {:error, "team name must be a string"}

  @max_member_name_bytes 64
  @max_member_role_bytes 256
  @max_member_soul_bytes 10_000

  defp validate_members(nil), do: :ok
  defp validate_members(members) when is_list(members) do
    cond do
      length(members) > @max_members ->
        {:error, "team may have at most #{@max_members} members"}
      true ->
        oversized = Enum.find(members, fn m ->
          (is_binary(m["name"]) and byte_size(m["name"]) > @max_member_name_bytes) or
          (is_binary(m["role"]) and byte_size(m["role"]) > @max_member_role_bytes) or
          (is_binary(m["soul"]) and byte_size(m["soul"]) > @max_member_soul_bytes)
        end)
        case oversized do
          nil -> :ok
          m -> {:error, "member '#{String.slice(m["name"] || "", 0, 32)}' exceeds field size limits"}
        end
    end
  end
  defp validate_members(_), do: {:error, "members must be a list"}

  defp validate_skills(skills) do
    validate_entries(skills, "skills", @max_skills)
  end

  defp validate_entries(nil, _label, _max), do: :ok
  defp validate_entries(entries, label, max) when is_list(entries) do
    cond do
      length(entries) > max ->
        {:error, "#{label} may have at most #{max} entries"}
      true ->
        # Validate IDs to prevent path traversal in adapters
        invalid_id = Enum.find(entries, fn entry ->
          id = entry["id"]
          not (is_binary(id) and Regex.match?(@id_re, id))
        end)
        case invalid_id do
          nil ->
            oversized = Enum.find(entries, fn entry ->
              body = entry["body"]
              is_binary(body) and byte_size(body) > @max_skill_body_bytes
            end)
            case oversized do
              nil -> :ok
              entry -> {:error, "#{label} entry '#{entry["id"]}' body exceeds #{@max_skill_body_bytes} bytes"}
            end
          entry -> {:error, "#{label} entry has invalid id: '#{entry["id"] || "missing"}'"}
        end
    end
  end
  defp validate_entries(_, label, _max), do: {:error, "#{label} must be a list"}

  defp validate_platforms(nil), do: :ok
  defp validate_platforms(platforms) when is_list(platforms) do
    invalid = Enum.find(platforms, fn p -> not is_binary(p) or p not in @valid_platforms end)
    case invalid do
      nil -> :ok
      p -> {:error, "unknown platform: '#{p}'"}
    end
  end
  defp validate_platforms(_), do: {:error, "platforms must be a list"}

  defp validate_knowledge(nil), do: :ok
  defp validate_knowledge(k) when is_binary(k) do
    if byte_size(k) > 100_000 do
      {:error, "knowledge exceeds maximum size of 100,000 bytes"}
    else
      :ok
    end
  end
  defp validate_knowledge(_), do: {:error, "knowledge must be a string"}

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp sanitize_team(team) do
    members =
      (team["members"] || [])
      |> Enum.map(fn m ->
        %{"name" => to_string(m["name"] || ""), "role" => to_string(m["role"] || "")}
        |> put_if_present("skills", m["skills"])
        |> put_if_present("soul", m["soul"])
      end)

    trimmed_name = if is_binary(team["name"]), do: String.trim(team["name"]), else: team["name"]

    %{"name" => trimmed_name, "members" => members}
    |> put_if_present("skills", team["skills"])
    |> put_if_present("knowledge", team["knowledge"])
    |> put_if_present("platforms", team["platforms"])
  end

  defp safe_integer(nil, default), do: default
  defp safe_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end
  defp safe_integer(val, _default) when is_integer(val), do: val
  defp safe_integer(_, default), do: default
end
