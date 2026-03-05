defmodule TeambridgeWeb.ApiController do
  use TeambridgeWeb, :controller

  alias Teambridge.Teams

  # Input validation limits
  @max_team_name_length 64
  @max_members 20
  @max_entry_size_bytes 102_400  # 100KB

  # TODO(v2): Add rate limiting per token to prevent abuse.
  # Consider using a library like Hammer or PlugAttack.

  def create_team(conn, %{"token" => token, "team" => team}) do
    with :ok <- validate_team(team) do
      :ok = Teams.put_team(token, team)

      conn
      |> put_status(:created)
      |> json(%{status: "ok"})
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

  def sync(conn, %{"token" => token, "platform" => platform, "hashes" => hashes}) do
    :ok = Teams.put_hashes(token, platform, hashes)
    {:ok, changes} = Teams.get_changes(token, platform)
    {:ok, buffer} = Teams.pull_buffer(token, platform)

    json(conn, %{changes: changes, buffer: buffer})
  end

  def push(conn, %{"token" => token, "platform" => platform, "entry" => entry}) do
    with :ok <- validate_entry_size(entry) do
      entry = Map.put(entry, "source_platform", platform)
      :ok = Teams.push_buffer(token, entry)

      json(conn, %{status: "ok"})
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  def pull(conn, %{"token" => token, "platform" => platform}) do
    {:ok, entries} = Teams.pull_buffer(token, platform)

    json(conn, %{entries: entries})
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
  defp validate_members(_), do: :ok

  defp validate_entry_size(entry) do
    encoded = Jason.encode!(entry)
    if byte_size(encoded) > @max_entry_size_bytes do
      {:error, "entry exceeds maximum size of #{@max_entry_size_bytes} bytes"}
    else
      :ok
    end
  end
end
