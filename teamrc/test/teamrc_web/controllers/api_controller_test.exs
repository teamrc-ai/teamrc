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

    test "returns updated_at and knowledge", %{conn: conn} do
      token = "tok_test_ua_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "UA Team", "members" => [], "knowledge" => "some knowledge"}
      Teamrc.Teams.put_team(token, team)

      conn = get(conn, "/api/teams/#{token}")
      resp = json_response(conn, 200)
      assert is_binary(resp["team"]["updated_at"])
      assert resp["team"]["knowledge"] == "some knowledge"
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
end
