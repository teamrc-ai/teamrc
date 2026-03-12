defmodule TeambridgeWeb.ApiControllerTest do
  use TeambridgeWeb.ConnCase, async: false

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
      Teambridge.Teams.put_team(token, team)

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
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

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
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/push", %{
          "token" => token,
          "platform" => "cursor",
          "entry" => %{"type" => "message", "content" => "hello"}
        })

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify entry is retrievable via pull
      conn2 =
        build_conn()
        |> get("/api/pull", %{"token" => token, "platform" => "claude_code"})

      resp = json_response(conn2, 200)
      assert length(resp["entries"]) == 1
    end
  end

  describe "GET /api/pull" do
    test "pulls buffer entries", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

      Teambridge.Teams.push_buffer(token, %{
        "type" => "message",
        "content" => "hello",
        "source_platform" => "cursor"
      })

      conn =
        conn
        |> get("/api/pull", %{"token" => token, "platform" => "claude_code"})

      body = json_response(conn, 200)
      assert is_list(body["entries"])
      assert length(body["entries"]) == 1
    end
  end

  describe "POST /api/sync edge cases" do
    test "sync with unregistered token returns 403", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sync", %{
          "token" => "tb_ak_new_team_#{:erlang.unique_integer([:positive])}",
          "platform" => "claude-code",
          "hashes" => %{"file.md" => "abc123"}
        })

      resp = json_response(conn, 403)
      assert resp["error"] =~ "not associated with any team"
    end
  end

  describe "push and pull round-trip" do
    test "push and pull round-trip preserves data", %{conn: conn} do
      token = "tb_ak_roundtrip_#{:erlang.unique_integer([:positive])}"
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

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

      # Pull from platform B
      conn2 =
        build_conn()
        |> get("/api/pull", %{"token" => token, "platform" => "openclaw"})

      resp = json_response(conn2, 200)
      assert length(resp["entries"]) == 1
      assert hd(resp["entries"])["content"] == "important finding"
    end

    test "push from platform A is not visible to platform A", %{conn: conn} do
      token = "tb_ak_self_filter_#{:erlang.unique_integer([:positive])}"
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/push", %{
        "token" => token,
        "platform" => "claude-code",
        "entry" => %{"type" => "memory", "content" => "my own note"}
      })

      # Pull from same platform — should NOT see own entry
      conn2 =
        build_conn()
        |> get("/api/pull", %{"token" => token, "platform" => "claude-code"})

      resp = json_response(conn2, 200)
      assert resp["entries"] == []
    end
  end
end
