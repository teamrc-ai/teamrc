defmodule TeambridgeWeb.ApiControllerTest do
  use TeambridgeWeb.ConnCase, async: false

  # Use the global Teambridge.Teams started by the app supervisor.
  # We don't need isolation here since each test uses unique tokens.

  describe "POST /api/teams" do
    test "creates a team", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Test Team", "agents" => ["agent1"]}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      assert json_response(conn, 201) == %{"status" => "ok"}
    end
  end

  describe "GET /api/teams/:token" do
    test "returns a team that exists", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Test Team"}
      Teambridge.Teams.put_team(token, team)

      conn = get(conn, "/api/teams/#{token}")
      assert json_response(conn, 200) == %{"team" => team}
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, "/api/teams/tok_nonexistent")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "POST /api/sync" do
    test "returns changes and buffer entries", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"

      # Set up hashes from another platform
      Teambridge.Teams.put_hashes(token, "cursor", %{"f1" => "h1"})

      # Push an entry from cursor
      Teambridge.Teams.push_buffer(token, %{
        "type" => "message",
        "content" => "hello",
        "source_platform" => "cursor"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sync", %{
          "token" => token,
          "platform" => "claude_code",
          "hashes" => %{"f2" => "h2"}
        })

      body = json_response(conn, 200)
      assert is_map(body["changes"])
      assert is_list(body["buffer"])
      assert length(body["buffer"]) == 1
    end
  end

  describe "POST /api/push" do
    test "pushes an entry to the buffer", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/push", %{
          "token" => token,
          "platform" => "cursor",
          "entry" => %{"type" => "message", "content" => "hello"}
        })

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify entry is in the buffer
      {:ok, entries} = Teambridge.Teams.pull_buffer(token, "claude_code")
      assert length(entries) == 1
      assert hd(entries)["source_platform"] == "cursor"
    end
  end

  describe "POST /api/pull" do
    test "pulls buffer entries", %{conn: conn} do
      token = "tok_test_#{:erlang.unique_integer([:positive])}"

      Teambridge.Teams.push_buffer(token, %{
        "type" => "message",
        "content" => "hello",
        "source_platform" => "cursor"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pull", %{"token" => token, "platform" => "claude_code"})

      body = json_response(conn, 200)
      assert is_list(body["entries"])
      assert length(body["entries"]) == 1
    end
  end
end
