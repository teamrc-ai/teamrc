defmodule TeambridgeWeb.ApiController do
  use TeambridgeWeb, :controller
  use TeambridgeWeb.Plugs.ApiErrorHandler

  require Logger
  alias Teambridge.Teams

  # Input validation limits
  @max_team_name_length 64
  @max_members 20
  @max_file_size_bytes 256_000  # 256KB per file
  @max_hash_length 128
  @max_platform_length 64
  @max_file_path_length 512
  @max_files_per_sync 100

  def create_team(conn, %{"token" => token, "team" => team}) do
    with :ok <- validate_team(team) do
      team = sanitize_team(team)
      {:ok, team_data} = Teams.put_team(token, team)

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

  def get_team(conn, %{"token" => token}) do
    case Teams.get_team(token) do
      {:ok, team} ->
        json(conn, %{team: team})

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

  @doc """
  Unified sync endpoint.

  Accepts: token, platform, hashes (map of file => hash), files (map of file => content).
  Returns: files that differ from other platforms.
  """
  def sync(conn, params) do
    token = params["token"]
    platform = params["platform"]
    hashes = params["hashes"] || %{}
    files = params["files"] || %{}

    with :ok <- validate_platform(platform),
         :ok <- validate_hashes(hashes),
         :ok <- validate_file_paths(hashes),
         :ok <- validate_file_paths(files),
         :ok <- validate_files(files),
         {:ok, result} <- Teams.sync(token, platform, hashes, files) do
      json(conn, %{changes: result.files})
    else
      {:error, :not_joined} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "token not associated with any team — run 'teambridge init' first"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc "Push a single entry (legacy / convenience). Wraps into sync."
  def push(conn, %{"token" => token, "platform" => platform, "entry" => entry}) do
    with :ok <- validate_platform(platform),
         :ok <- validate_entry_size(entry) do
      entry = Map.put(entry, "source_platform", platform)

      case Teams.push_buffer(token, entry) do
        :ok ->
          json(conn, %{status: "ok"})

        {:error, :not_joined} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "token not associated with any team — run 'teambridge init' first"})

        {:error, :buffer_full} ->
          conn
          |> put_status(429)
          |> json(%{error: "buffer full, try again later"})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  def pull(conn, %{"token" => token, "platform" => platform}) do
    case Teams.pull_buffer(token, platform) do
      {:ok, entries} ->
        json(conn, %{entries: entries})

      {:error, :not_joined} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "token not associated with any team — run 'teambridge init' first"})
    end
  end

  def sync_check(conn, %{"token" => token, "since" => since_str}) do
    case Integer.parse(since_str) do
      {since, ""} ->
        case Teams.check_changed(token, since) do
          {:ok, changed} ->
            json(conn, %{changed: changed})

          {:error, :not_joined} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "token not associated with any team — run 'teambridge init' first"})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "since must be a Unix timestamp integer"})
    end
  end

  def sync_check(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "token and since parameters are required"})
  end

  # --- Input Validation ---

  defp validate_team(team) do
    with :ok <- validate_team_name(team["name"]),
         :ok <- validate_members(team["members"]) do
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
    if length(members) > @max_members do
      {:error, "team may have at most #{@max_members} members"}
    else
      :ok
    end
  end
  defp validate_members(_), do: {:error, "members must be a list"}

  defp validate_files(files) when is_map(files) do
    oversized =
      Enum.find(files, fn {_name, content} ->
        is_binary(content) and byte_size(content) > @max_file_size_bytes
      end)

    case oversized do
      nil -> :ok
      {name, _} -> {:error, "file #{name} exceeds maximum size of #{@max_file_size_bytes} bytes"}
    end
  end
  defp validate_files(_), do: :ok

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp sanitize_team(team) do
    members =
      (team["members"] || [])
      |> Enum.map(fn m ->
        %{"name" => to_string(m["name"] || ""), "role" => to_string(m["role"] || "")}
        |> put_if_present("rules", m["rules"])
        |> put_if_present("skills", m["skills"])
      end)

    %{"name" => team["name"], "members" => members}
    |> put_if_present("rules", team["rules"])
    |> put_if_present("skills", team["skills"])
  end

  defp validate_entry_size(entry) do
    encoded = Jason.encode!(entry)
    if byte_size(encoded) > @max_file_size_bytes do
      {:error, "entry exceeds maximum size of #{@max_file_size_bytes} bytes"}
    else
      :ok
    end
  end

  defp validate_platform(nil), do: {:error, "platform is required"}
  defp validate_platform(platform) when is_binary(platform) do
    cond do
      byte_size(platform) > @max_platform_length ->
        {:error, "platform name too long"}
      not Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/, platform) ->
        {:error, "platform must be alphanumeric (hyphens and underscores allowed)"}
      true ->
        :ok
    end
  end
  defp validate_platform(_), do: {:error, "platform must be a string"}

  defp validate_hashes(hashes) when is_map(hashes) do
    invalid =
      Enum.find(hashes, fn {_path, hash} ->
        not is_binary(hash) or byte_size(hash) > @max_hash_length
      end)

    case invalid do
      nil -> :ok
      {path, _} -> {:error, "invalid hash for file: #{path}"}
    end
  end
  defp validate_hashes(_), do: {:error, "hashes must be a map"}

  defp validate_file_paths(map) when is_map(map) do
    if map_size(map) > @max_files_per_sync do
      {:error, "too many files (max #{@max_files_per_sync})"}
    else
      invalid =
        Enum.find(Map.keys(map), fn path ->
          not is_binary(path) or
            byte_size(path) > @max_file_path_length or
            String.contains?(path, "..") or
            String.starts_with?(path, "/")
        end)

      case invalid do
        nil -> :ok
        path -> {:error, "invalid file path: #{path}"}
      end
    end
  end
  defp validate_file_paths(_), do: :ok
end
