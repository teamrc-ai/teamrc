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

    test "creates a team with knowledge", %{conn: conn} do
      token = "tok_test_k_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Knowledge Team", "members" => [], "knowledge" => "shared notes"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 201)
      assert resp["team"]["knowledge"] == "shared notes"
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

    test "returns content hashes and knowledge", %{conn: conn} do
      token = "tok_test_ua_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "UA Team", "members" => [], "knowledge" => "some knowledge"}
      Teamrc.Teams.put_team(token, team)

      conn = get(conn, "/api/teams/#{token}")
      resp = json_response(conn, 200)
      assert is_binary(resp["team"]["hash"])
      assert is_binary(resp["team"]["members_hash"])
      assert is_binary(resp["team"]["skills_hash"])
      assert is_binary(resp["team"]["knowledge_hash"])
      assert String.length(resp["team"]["hash"]) == 64
      assert resp["team"]["knowledge"] == "some knowledge"
    end
  end

  describe "POST /api/teams/preview" do
    test "returns team data for valid invite", %{conn: conn} do
      {:ok, invite_code, _team_id} = Teamrc.Teams.create_team_with_invite(%{
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

  describe "DELETE /api/token/:token/erase" do
    test "erases all token_teams for the requesting token", %{conn: conn} do
      token = "trc_ak_erase_#{:erlang.unique_integer([:positive])}"

      # Create two teams associated with this token
      {:ok, _team1} = Teamrc.Teams.put_team(token, %{"name" => "Erase Team 1", "members" => []})
      {:ok, _team2} = Teamrc.Teams.put_team(token, %{"name" => "Erase Team 2", "members" => []}, nil)

      # Verify the token has team associations
      {:ok, teams_before} = Teamrc.Teams.get_teams(token)
      assert length(teams_before) >= 1

      # Call the erasure endpoint
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/#{token}/erase")

      resp = json_response(conn, 200)
      assert resp["status"] == "erased"
      assert resp["teams_removed"] >= 1

      # Verify all token_teams rows are gone
      assert Teamrc.Teams.get_teams(token) == :error
    end

    test "erasure only affects the requesting token, not other tokens", %{conn: conn} do
      token_a = "trc_ak_erase_a_#{:erlang.unique_integer([:positive])}"
      token_b = "trc_ak_erase_b_#{:erlang.unique_integer([:positive])}"

      # Create a team and have both tokens join it
      {:ok, _team} = Teamrc.Teams.put_team(token_a, %{"name" => "Shared Team", "members" => []})
      {:ok, team_data} = Teamrc.Teams.get_team(token_a)
      team_id = team_data["id"]

      # Have token_b join the same team via invite
      {:ok, invite_code, _expires} = Teamrc.Teams.create_invite(token_a, 24, team_id)
      {:ok, _} = Teamrc.Teams.join_by_invite(invite_code, token_b)

      # Verify both tokens can see the team
      assert {:ok, _} = Teamrc.Teams.get_team(token_a)
      assert {:ok, _} = Teamrc.Teams.get_team(token_b)

      # Erase token_a
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/#{token_a}/erase")

      resp = json_response(conn, 200)
      assert resp["status"] == "erased"
      assert resp["teams_removed"] >= 1

      # token_a should have no teams
      assert Teamrc.Teams.get_teams(token_a) == :error

      # token_b should still have access to the team
      assert {:ok, _} = Teamrc.Teams.get_team(token_b)
    end

    test "returns success even with no teams to erase", %{conn: conn} do
      token = "trc_ak_erase_empty_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/#{token}/erase")

      resp = json_response(conn, 200)
      assert resp["status"] == "erased"
      assert resp["teams_removed"] == 0
    end
  end

  describe "GET /api/teams/:token/head" do
    test "returns hashes for a valid token", %{conn: conn} do
      token = "tok_head_api_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "Head Team", "members" => [%{"name" => "alice", "role" => "dev"}]})

      conn = get(conn, "/api/teams/#{token}/head")
      resp = json_response(conn, 200)

      assert is_binary(resp["hash"])
      assert is_binary(resp["members_hash"])
      assert is_binary(resp["skills_hash"])
      assert is_binary(resp["knowledge_hash"])
      assert String.length(resp["hash"]) == 64
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, "/api/teams/tok_head_unknown/head")
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "hashes match full team response", %{conn: conn} do
      token = "tok_head_match_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "Match Team", "members" => [], "knowledge" => "notes\n"})

      head_conn = get(conn, "/api/teams/#{token}/head")
      head_resp = json_response(head_conn, 200)

      full_conn = get(build_conn(), "/api/teams/#{token}")
      full_resp = json_response(full_conn, 200)

      assert head_resp["hash"] == full_resp["team"]["hash"]
      assert head_resp["members_hash"] == full_resp["team"]["members_hash"]
      assert head_resp["skills_hash"] == full_resp["team"]["skills_hash"]
      assert head_resp["knowledge_hash"] == full_resp["team"]["knowledge_hash"]
    end
  end

  describe "POST /api/teams conflict detection" do
    test "returns 409 on hash conflict", %{conn: conn} do
      token = "tok_conflict_api_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teamrc.Teams.put_team(token, %{"name" => "Conflict Team", "members" => [%{"name" => "alice", "role" => "dev"}]})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{
          "token" => token,
          "base_hash" => "0000000000000000000000000000000000000000000000000000000000000000",
          "team" => %{
            "name" => "Conflict Team",
            "members" => [%{"name" => "charlie", "role" => "ops"}]
          }
        })

      resp = json_response(conn, 409)
      assert resp["error"] == "conflict"
      assert is_binary(resp["server_hash"])
      # Component hashes are not exposed in 409 to prevent hash oracle attacks
      refute resp["members_hash"]
      refute resp["skills_hash"]
      refute resp["knowledge_hash"]
    end

    test "succeeds with matching base_hash", %{conn: conn} do
      token = "tok_ff_api_#{:erlang.unique_integer([:positive])}"
      {:ok, created} = Teamrc.Teams.put_team(token, %{"name" => "FF Team", "members" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{
          "token" => token,
          "base_hash" => created["hash"],
          "team" => %{
            "name" => "FF Team",
            "members" => [%{"name" => "bob", "role" => "qa"}]
          }
        })

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "FF Team"
      assert length(resp["team"]["members"]) == 1
    end
  end

  describe "DELETE /api/token/:token/erase (auth required)" do
    setup do
      # Disable skip_auth to test that signature verification is required
      original = Application.get_env(:teamrc, :skip_auth, false)
      Application.put_env(:teamrc, :skip_auth, false)
      on_exit(fn -> Application.put_env(:teamrc, :skip_auth, original) end)
      :ok
    end

    test "rejects requests without a valid signature", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/trc_ak_nosig/erase")

      resp = json_response(conn, 401)
      assert resp["error"] == "unauthorized"
    end
  end
end
