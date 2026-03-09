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
      team = sanitize_team(team)
      team_id = params["team_id"]
      {:ok, team_data} = Teams.put_team(token, team, team_id)

      conn
      |> put_status(:created)
      |> json(%{team: team_data})
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
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

  # --- Input Validation ---

  defp validate_team(team) do
    with :ok <- validate_team_name(team["name"]),
         :ok <- validate_members(team["members"]),
         :ok <- validate_skills(team["skills"]),
         :ok <- validate_knowledge(team["knowledge"]) do
      :ok
    end
  end

  defp validate_team_name(nil), do: :ok
  defp validate_team_name(name) when is_binary(name) do
    cond do
      byte_size(name) > @max_team_name_length ->
        {:error, "team name must be #{@max_team_name_length} characters or fewer"}
      not Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9 _-]*$/, name) ->
        {:error, "team name must be alphanumeric (hyphens, underscores, and spaces allowed)"}
      true ->
        :ok
    end
  end
  defp validate_team_name(_), do: {:error, "team name must be a string"}

  defp validate_members(nil), do: :ok
  defp validate_members(members) when is_list(members) do
    if length(members) >= @max_members do
      {:error, "team may have at most #{@max_members} members"}
    else
      :ok
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

    %{"name" => team["name"], "members" => members}
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
