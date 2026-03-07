defmodule TeamrcWeb.ApiControllerTest do
  use TeamrcWeb.ConnCase, async: false

  describe "POST /api/teams" do
    test "creates a team", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Test Team", "agents" => ["agent1"]}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "Test Team"
      assert resp["team"]["id"]
    end
  end

  describe "GET /api/teams/:token" do
    test "returns a team that exists", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Test Team", "members" => []}
      Teamrc.Teams.put_team(token, team)

      conn = get(conn, "/api/teams/#{token}")
      resp = json_response(conn, 200)
      assert resp["team"]["name"] == "Test Team"
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, "/api/teams/tok_nonexistent")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "POST /api/sync" do
    test "returns changes from other platforms", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      # Platform A syncs with content
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/sync", %{
        "token" => token,
        "platform" => "cursor",
        "hashes" => %{"team.yaml" => "h1"},
        "files" => %{"team.yaml" => "name: my-team"}
      })

      # Platform B syncs with different hash — should get the content
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sync", %{
          "token" => token,
          "platform" => "claude_code",
          "hashes" => %{"team.yaml" => "old_hash"}
        })

      body = json_response(conn, 200)
      assert is_map(body["changes"])
      assert body["changes"]["team.yaml"]["content"] == "name: my-team"
      assert is_integer(body["changes"]["team.yaml"]["updated_at"])
    end
  end

  describe "POST /api/push" do
    test "pushes an entry to the buffer", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/push", %{
          "token" => token,
          "platform" => "cursor",
          "entry" => %{"type" => "message", "content" => "hello"}
        })

      assert json_response(conn, 200) == %{"status" => "ok"}

    end
  end

  describe "POST /api/sync edge cases" do
    test "sync with unregistered token returns 403", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sync", %{
          "token" => "trc_ak_new_team_#{:erlang.unique_integer([:positive])}",
          "platform" => "claude-code",
          "hashes" => %{"file.md" => "abc123"}
        })

      resp = json_response(conn, 403)
      assert resp["error"] =~ "not associated with any team"
    end
  end

  describe "push round-trip" do
    test "push stores data retrievable via internal pull_buffer", %{conn: conn} do
      token = "trc_ak_roundtrip_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      # Push from platform A
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/push", %{
        "token" => token,
        "platform" => "claude-code",
        "entry" => %{
          "type" => "memory",
          "content" => "important finding",
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      })

      # Verify via internal API
      {:ok, entries} = Teamrc.Teams.pull_buffer(token, "openclaw")
      assert length(entries) == 1
      assert hd(entries)["content"] == "important finding"
    end

    test "push from platform A is not visible to platform A", %{conn: conn} do
      token = "trc_ak_self_filter_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/push", %{
        "token" => token,
        "platform" => "claude-code",
        "entry" => %{"type" => "memory", "content" => "my own note"}
      })

      # Verify via internal API — same platform should not see own entry
      {:ok, entries} = Teamrc.Teams.pull_buffer(token, "claude-code")
      assert entries == []
    end
  end

  describe "POST /api/teams/preview" do
    test "returns team data for valid invite", %{conn: conn} do
      {:ok, invite_code} = Teamrc.Teams.create_team_with_invite(%{
        "name" => "preview-api-team",
        "members" => [%{"name" => "dev", "role" => "backend"}]
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/preview", %{"invite_code" => invite_code})

      resp = json_response(conn, 200)
      assert resp["team"]["name"] == "preview-api-team"
      assert length(resp["team"]["members"]) == 1
    end

    test "returns 404 for invalid invite code", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/preview", %{"invite_code" => "trc_inv_bogus"})

      resp = json_response(conn, 404)
      assert resp["error"] == "invalid_invite"
    end
  end

  describe "POST /api/teams/invite" do
    test "returns invite code for team member", %{conn: conn} do
      token = "trc_ak_inviter_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "invite-api-team", "members" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/invite", %{"token" => token})

      resp = json_response(conn, 200)
      assert String.starts_with?(resp["invite_code"], "trc_inv_")
      assert resp["expires_at"]
    end

    test "returns 403 for non-member", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/invite", %{"token" => "trc_ak_stranger_#{:erlang.unique_integer([:positive])}"})

      resp = json_response(conn, 403)
      assert resp["error"] == "not a team member"
    end
  end

  describe "GET /api/log" do
    test "returns entries for team member", %{conn: conn} do
      token = "trc_ak_log_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      # Push some content
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/push", %{
        "token" => token,
        "platform" => "cursor",
        "entry" => %{"type" => "knowledge:notes", "content" => "test finding"}
      })

      conn = get(conn, "/api/log?token=#{token}")
      resp = json_response(conn, 200)
      assert is_list(resp["entries"])
      assert length(resp["entries"]) == 1

      entry = hd(resp["entries"])
      assert entry["type"] == "knowledge:notes"
      assert entry["content"] == "test finding"
      assert entry["source_platform"] == "cursor"
      assert entry["pushed_by"] == token
      assert entry["timestamp"]
    end

    test "returns 403 for unknown token", %{conn: conn} do
      conn = get(conn, "/api/log?token=trc_ak_unknown_#{:erlang.unique_integer([:positive])}")
      resp = json_response(conn, 403)
      assert resp["error"] == "not a team member"
    end
  end

  describe "sync pushed_by attribution" do
    test "sync response includes pushed_by in changed files", %{conn: conn} do
      token = "trc_ak_attr_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "test", "members" => []})

      # Platform A syncs with content
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/sync", %{
        "token" => token,
        "platform" => "cursor",
        "hashes" => %{"team.yaml" => "h1"},
        "files" => %{"team.yaml" => "name: my-team"}
      })

      # Platform B syncs with different hash — should get content with pushed_by
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sync", %{
          "token" => token,
          "platform" => "claude-code",
          "hashes" => %{"team.yaml" => "old_hash"}
        })

      body = json_response(conn, 200)
      assert body["changes"]["team.yaml"]["pushed_by"] == token
    end
  end
end
