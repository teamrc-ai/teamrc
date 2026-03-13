defmodule TeamrcWeb.AccountControllerTest do
  use TeamrcWeb.ConnCase, async: false

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Accounts.MachineToken
  alias Teamrc.Schema.{Team, Member, TokenTeam}

  setup %{conn: conn} do
    # Create user via fixture
    user = Teamrc.AccountsFixtures.user_fixture(%{email: "test@example.com"})

    # Accept terms so require_authenticated_user doesn't redirect
    {:ok, user} =
      Teamrc.Accounts.accept_terms(user, "2026-03-11")

    # Create two machine tokens
    {:ok, mt1} =
      %MachineToken{}
      |> MachineToken.changeset(%{
        user_id: user.id,
        token: "trc_ak_machine1_token",
        machine_name: "laptop"
      })
      |> Repo.insert()

    {:ok, mt2} =
      %MachineToken{}
      |> MachineToken.changeset(%{
        user_id: user.id,
        token: "trc_ak_machine2_token",
        machine_name: "desktop"
      })
      |> Repo.insert()

    # Create a team with members and skills
    team =
      %Team{}
      |> Team.changeset(%{name: "test-team", skills: [%{"id" => "s1", "body" => "skill1"}]})
      |> Repo.insert!()

    Ecto.build_assoc(team, :members)
    |> Member.changeset(%{name: "agent1", role: "backend-dev"})
    |> Repo.insert!()

    # Associate token1 with the team
    %TokenTeam{}
    |> TokenTeam.changeset(%{token: mt1.token, team_id: team.id})
    |> Repo.insert!()

    # Log in via session (session_api pipeline uses fetch_session + fetch_current_scope_for_user)
    conn =
      conn
      |> log_in_user(user)
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", TeamrcWeb.Endpoint.url())

    %{
      conn: conn,
      user: user,
      token1: mt1,
      token2: mt2,
      team: team
    }
  end

  describe "unauthenticated access" do
    test "GET /api/account returns 401 JSON when not logged in", %{conn: _conn} do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> get("/api/account")

      assert json_response(conn, 401)["error"] == "authentication required"
    end

    test "GET /api/account/teams returns 401 JSON when not logged in", %{conn: _conn} do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> get("/api/account/teams")

      assert json_response(conn, 401)["error"] == "authentication required"
    end
  end

  describe "GET /api/account" do
    test "returns account and machines", %{conn: conn, user: user} do
      conn = get(conn, "/api/account")
      resp = json_response(conn, 200)

      assert resp["account"]["id"] == user.id
      assert resp["account"]["email"] == "test@example.com"
      assert length(resp["machines"]) == 2

      machine = Enum.find(resp["machines"], &(&1["machine_name"] == "laptop"))
      assert machine["token"] == "trc_ak_machi..."
    end
  end

  describe "GET /api/account/teams" do
    test "returns teams with hashed participants", %{conn: conn, team: team} do
      conn = get(conn, "/api/account/teams")
      resp = json_response(conn, 200)

      assert length(resp["teams"]) == 1
      team_resp = hd(resp["teams"])
      assert team_resp["id"] == team.id
      assert team_resp["name"] == "test-team"
      assert team_resp["agent_count"] == 1
      assert team_resp["skill_count"] == 1
      assert is_list(team_resp["participants"])
      refute "test@example.com" in team_resp["participants"]
    end

    test "returns empty list when no active tokens", %{conn: conn, token1: token1, token2: token2} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      token1
      |> Ecto.Changeset.change(%{revoked_at: now})
      |> Repo.update!()

      token2
      |> Ecto.Changeset.change(%{revoked_at: now})
      |> Repo.update!()

      conn = get(conn, "/api/account/teams")
      resp = json_response(conn, 200)

      assert resp["teams"] == []
    end
  end

  describe "DELETE /api/account/machines/:token" do
    test "revokes the token", %{conn: conn, token1: token1} do
      conn = delete(conn, "/api/account/machines/#{token1.token}")
      resp = json_response(conn, 200)

      assert resp["status"] == "revoked"

      # Verify token is revoked in DB
      updated = Repo.get!(MachineToken, token1.id)
      refute is_nil(updated.revoked_at)

      # Verify token_teams row is deleted
      token_val = token1.token
      assert Repo.all(from tt in TokenTeam, where: tt.token == ^token_val) == []
    end

    test "returns 404 for token not owned by caller", %{conn: conn} do
      conn = delete(conn, "/api/account/machines/trc_ak_someone_else")
      assert json_response(conn, 404)["error"] == "token_not_found"
    end
  end

  describe "POST /api/account/reassociate" do
    test "copies team associations to new token", %{conn: conn, token2: token2, team: team} do
      # token1 is in team, token2 is not
      conn =
        conn
        |> post("/api/account/reassociate", %{"new_token" => token2.token, "token" => token2.token})

      resp = json_response(conn, 200)
      assert resp["reassociated"] == 1

      # Verify token2 is now associated with the team
      token_val = token2.token
      token_team = Repo.one(from tt in TokenTeam, where: tt.token == ^token_val)
      assert token_team.team_id == team.id
    end

    test "returns error for unknown token", %{conn: conn} do
      conn =
        conn
        |> post("/api/account/reassociate", %{
          "new_token" => "trc_ak_unknown_token",
          "token" => "trc_ak_unknown_token"
        })

      assert json_response(conn, 400)["error"] =~ "non-revoked token"
    end

    test "returns error for revoked token", %{conn: conn, token2: token2} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      token2
      |> Ecto.Changeset.change(%{revoked_at: now})
      |> Repo.update!()

      conn =
        conn
        |> post("/api/account/reassociate", %{
          "new_token" => token2.token,
          "token" => token2.token
        })

      assert json_response(conn, 400)["error"] =~ "non-revoked token"
    end
  end
end
