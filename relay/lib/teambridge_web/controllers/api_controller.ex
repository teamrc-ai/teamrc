defmodule TeambridgeWeb.ApiController do
  use TeambridgeWeb, :controller

  alias Teambridge.Teams

  def create_team(conn, %{"token" => token, "team" => team}) do
    :ok = Teams.put_team(token, team)

    conn
    |> put_status(:created)
    |> json(%{status: "ok"})
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
    entry = Map.put(entry, "source_platform", platform)
    :ok = Teams.push_buffer(token, entry)

    json(conn, %{status: "ok"})
  end

  def pull(conn, %{"token" => token, "platform" => platform}) do
    {:ok, entries} = Teams.pull_buffer(token, platform)

    json(conn, %{entries: entries})
  end
end
