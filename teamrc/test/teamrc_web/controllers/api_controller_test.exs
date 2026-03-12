defmodule TeamrcWeb.ApiControllerTest do
  use TeamrcWeb.ConnCase, async: false

  describe "POST /api/teams" do
    test "creates a team", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "Test Team", "members" => [%{"name" => "agent1", "role" => "developer"}]}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "Test Team"
      assert resp["team"]["id"]
      assert length(resp["team"]["members"]) == 1
      assert hd(resp["team"]["members"])["name"] == "agent1"
    end

    test "creates a team with knowledge", %{conn: conn} do
      token = "trc_ak_test_k_#{:erlang.unique_integer([:positive])}"
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
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
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
      token = "trc_ak_test_ua_#{:erlang.unique_integer([:positive])}"
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
        "members" => [%{"name" => "dev", "role" => "backend", "soul" => "I write APIs"}],
        "knowledge" => "secret team knowledge"
      })

      # Need a token in the body for the VerifySignature plug to extract (skip_auth mode)
      token = "trc_ak_preview_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/preview", %{"invite_code" => invite_code, "token" => token})

      resp = json_response(conn, 200)
      assert resp["team"]["name"] == "preview-api-team"
      assert length(resp["team"]["members"]) == 1

      # Knowledge should be redacted from preview
      refute resp["team"]["knowledge"]

      # Member souls should be redacted from preview
      Enum.each(resp["team"]["members"], fn member ->
        refute Map.has_key?(member, "soul")
      end)
    end

    test "returns 404 for invalid invite code", %{conn: conn} do
      token = "trc_ak_preview_bad_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/preview", %{"invite_code" => "trc_inv_bogus", "token" => token})

      resp = json_response(conn, 404)
      assert resp["error"] == "invalid_invite"
    end
  end

  describe "POST /api/teams/invite" do
    test "returns invite code for team member with default TTL", %{conn: conn} do
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

    test "returns invite code with custom TTL", %{conn: conn} do
      token = "trc_ak_inviter_ttl_#{:erlang.unique_integer([:positive])}"
      Teamrc.Teams.put_team(token, %{"name" => "invite-ttl-team", "members" => []})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/invite", %{"token" => token, "ttl_hours" => 48})

      resp = json_response(conn, 200)
      assert String.starts_with?(resp["invite_code"], "trc_inv_")
      assert resp["expires_at"]

      # Parse the expires_at and verify it's roughly 48 hours from now
      {:ok, expires_at, _} = DateTime.from_iso8601(resp["expires_at"])
      diff_seconds = DateTime.diff(expires_at, DateTime.utc_now())
      # Should be between 47 and 49 hours (allowing for test execution time)
      assert diff_seconds > 47 * 3600
      assert diff_seconds < 49 * 3600
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
      assert resp["status"] == "disconnected"
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
      assert resp["status"] == "disconnected"
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
      assert resp["status"] == "disconnected"
      assert resp["teams_removed"] == 0
    end

    test "scoped erase with team_id removes only that team association", %{conn: conn} do
      token = "trc_ak_erase_scoped_#{:erlang.unique_integer([:positive])}"

      # Create two teams for this token
      {:ok, team_a} = Teamrc.Teams.put_team(token, %{"name" => "Keep Team", "members" => []})
      team_a_id = team_a["id"]

      {:ok, invite_code, _} = Teamrc.Teams.create_team_with_invite(%{
        "name" => "Remove Team",
        "members" => []
      })
      {:ok, team_b} = Teamrc.Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # Verify token has two teams
      {:ok, teams_before} = Teamrc.Teams.get_teams(token)
      assert length(teams_before) == 2

      # Erase only team_b
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/#{token}/erase?team_id=#{team_b_id}")

      resp = json_response(conn, 200)
      assert resp["status"] == "disconnected"
      assert resp["teams_removed"] == 1

      # Team A should still be accessible
      assert {:ok, got_a} = Teamrc.Teams.get_team(token, team_a_id)
      assert got_a["name"] == "Keep Team"

      # Team B should no longer be accessible
      assert :error = Teamrc.Teams.get_team(token, team_b_id)
    end

    test "scoped erase does not affect other tokens' associations", %{conn: conn} do
      token_a = "trc_ak_erase_sc_a_#{:erlang.unique_integer([:positive])}"
      token_b = "trc_ak_erase_sc_b_#{:erlang.unique_integer([:positive])}"

      # Create a team with token_a
      {:ok, team_data} = Teamrc.Teams.put_team(token_a, %{"name" => "Shared Scoped", "members" => []})
      team_id = team_data["id"]

      # Have token_b join the same team
      {:ok, invite_code, _} = Teamrc.Teams.create_invite(token_a, 24, team_id)
      {:ok, _} = Teamrc.Teams.join_by_invite(invite_code, token_b)

      # Erase only token_a's association with this team
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/token/#{token_a}/erase?team_id=#{team_id}")

      resp = json_response(conn, 200)
      assert resp["teams_removed"] == 1

      # token_a should not see the team
      assert :error = Teamrc.Teams.get_team(token_a, team_id)

      # token_b should still see the team
      assert {:ok, _} = Teamrc.Teams.get_team(token_b, team_id)
    end
  end

  describe "POST /api/join" do
    test "joins a team with valid invite code", %{conn: conn} do
      # Create a team with an invite
      {:ok, invite_code, _team_id} = Teamrc.Teams.create_team_with_invite(%{
        "name" => "join-api-team",
        "members" => [%{"name" => "bot", "role" => "helper"}]
      })

      token = "trc_ak_joiner_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/join", %{"invite_code" => invite_code, "token" => token})

      resp = json_response(conn, 200)
      assert resp["team"]["name"] == "join-api-team"
      assert length(resp["team"]["members"]) == 1
      assert resp["token"] == token
    end

    test "returns 404 for invalid invite code", %{conn: conn} do
      token = "trc_ak_joiner_bad_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/join", %{"invite_code" => "trc_inv_nonexistent", "token" => token})

      resp = json_response(conn, 404)
      assert resp["error"] == "invalid_invite"
    end

    test "returns 404 for expired invite code", %{conn: conn} do
      {:ok, invite_code, _team_id} = Teamrc.Teams.create_team_with_invite(%{
        "name" => "expired-join-api-team",
        "members" => []
      })

      # Expire the invite
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -3600)
      import Ecto.Query
      Teamrc.Repo.update_all(
        from(i in Teamrc.Schema.Invite, where: i.code == ^invite_code),
        set: [expires_at: past]
      )

      token = "trc_ak_joiner_exp_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/join", %{"invite_code" => invite_code, "token" => token})

      resp = json_response(conn, 404)
      assert resp["error"] == "invalid_invite"
    end
  end

  describe "GET /api/teams/clone/:clone_token" do
    test "returns team data for valid public clone token", %{conn: conn} do
      # Create a team, claim ownership, set public
      token = "trc_ak_clone_api_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teamrc.Teams.put_team(token, %{
        "name" => "clone-api-team",
        "members" => [%{"name" => "dev", "role" => "backend"}],
        "knowledge" => "private knowledge"
      })
      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Create user, link token, claim ownership
      {:ok, user} = Teamrc.Accounts.register_user(%{
        "email" => "clone_api_#{:erlang.unique_integer([:positive])}@test.com",
        "terms_accepted" => "true"
      })
      {:ok, _} = Teamrc.Accounts.link_machine_token(user.id, token, "test-machine")
      {:ok, :claimed} = Teamrc.Teams.claim_ownership(token, claim_secret)

      # Set visibility to public
      {:ok, updated} = Teamrc.Teams.set_visibility(token, team_id, "public")
      clone_token = updated.clone_token

      conn = get(conn, "/api/teams/clone/#{clone_token}")
      resp = json_response(conn, 200)

      assert resp["team"]["name"] == "clone-api-team"
      assert length(resp["team"]["members"]) == 1

      # Knowledge should be redacted from clone
      refute resp["team"]["knowledge"]
    end

    test "returns 404 for invalid clone token", %{conn: conn} do
      conn = get(conn, "/api/teams/clone/trc_cl_nonexistent")
      resp = json_response(conn, 404)
      assert resp["error"] == "invalid_clone_token"
    end
  end

  describe "POST /api/teams/visibility" do
    setup do
      token = "trc_ak_vis_api_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teamrc.Teams.put_team(token, %{
        "name" => "vis-api-team",
        "members" => []
      })
      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Create user and link token
      {:ok, user} = Teamrc.Accounts.register_user(%{
        "email" => "vis_api_#{:erlang.unique_integer([:positive])}@test.com",
        "terms_accepted" => "true"
      })
      {:ok, _} = Teamrc.Accounts.link_machine_token(user.id, token, "test-machine")

      %{token: token, team_id: team_id, claim_secret: claim_secret, user: user}
    end

    test "owner can set visibility to public", %{conn: conn, token: token, team_id: team_id, claim_secret: claim_secret} do
      {:ok, :claimed} = Teamrc.Teams.claim_ownership(token, claim_secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/visibility", %{
          "token" => token,
          "team_id" => team_id,
          "visibility" => "public"
        })

      resp = json_response(conn, 200)
      assert resp["visibility"] == "public"
      assert is_binary(resp["clone_token"])
    end

    test "owner can set visibility to private", %{conn: conn, token: token, team_id: team_id, claim_secret: claim_secret} do
      {:ok, :claimed} = Teamrc.Teams.claim_ownership(token, claim_secret)

      # First set public, then private
      Teamrc.Teams.set_visibility(token, team_id, "public")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/visibility", %{
          "token" => token,
          "team_id" => team_id,
          "visibility" => "private"
        })

      resp = json_response(conn, 200)
      assert resp["visibility"] == "private"
    end

    test "non-owner gets forbidden", %{conn: conn, token: token, team_id: team_id} do
      # Token is a member but not the owner (no claim)
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/visibility", %{
          "token" => token,
          "team_id" => team_id,
          "visibility" => "public"
        })

      resp = json_response(conn, 403)
      assert resp["error"] =~ "owner"
    end

    test "non-member gets forbidden", %{conn: conn, team_id: team_id} do
      other_token = "trc_ak_vis_other_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/visibility", %{
          "token" => other_token,
          "team_id" => team_id,
          "visibility" => "public"
        })

      resp = json_response(conn, 403)
      assert resp["error"] =~ "not a team member"
    end

    test "invalid visibility value returns 400", %{conn: conn, token: token, team_id: team_id, claim_secret: claim_secret} do
      {:ok, :claimed} = Teamrc.Teams.claim_ownership(token, claim_secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/visibility", %{
          "token" => token,
          "team_id" => team_id,
          "visibility" => "invalid"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "public"
    end
  end

  describe "POST /api/teams/claim" do
    test "valid claim secret with linked account succeeds", %{conn: conn} do
      token = "trc_ak_claim_api_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teamrc.Teams.put_team(token, %{
        "name" => "claim-api-team",
        "members" => []
      })
      claim_secret = team_data["owner_claim_secret"]

      # Create user and link token
      {:ok, user} = Teamrc.Accounts.register_user(%{
        "email" => "claim_api_#{:erlang.unique_integer([:positive])}@test.com",
        "terms_accepted" => "true"
      })
      {:ok, _} = Teamrc.Accounts.link_machine_token(user.id, token, "test-machine")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/claim", %{
          "token" => token,
          "claim_secret" => claim_secret
        })

      resp = json_response(conn, 200)
      assert resp["status"] == "claimed"
    end

    test "invalid secret returns 404", %{conn: conn} do
      token = "trc_ak_claim_bad_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teamrc.Teams.put_team(token, %{
        "name" => "claim-bad-team",
        "members" => []
      })

      {:ok, user} = Teamrc.Accounts.register_user(%{
        "email" => "claim_bad_#{:erlang.unique_integer([:positive])}@test.com",
        "terms_accepted" => "true"
      })
      {:ok, _} = Teamrc.Accounts.link_machine_token(user.id, token, "test-machine")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/claim", %{
          "token" => token,
          "claim_secret" => "trc_ocs_wrong_secret"
        })

      resp = json_response(conn, 404)
      assert resp["error"] =~ "invalid"
    end

    test "no linked account returns 403", %{conn: conn} do
      token = "trc_ak_claim_noacct_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teamrc.Teams.put_team(token, %{
        "name" => "claim-noacct-team",
        "members" => []
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/claim", %{
          "token" => token,
          "claim_secret" => team_data["owner_claim_secret"]
        })

      resp = json_response(conn, 403)
      assert resp["error"] =~ "link your account"
    end
  end

  describe "GET /api/teams/all/:token" do
    test "returns all teams for a token with multiple teams", %{conn: conn} do
      token = "trc_ak_all_multi_#{:erlang.unique_integer([:positive])}"

      {:ok, _team_a} = Teamrc.Teams.put_team(token, %{"name" => "Team All A", "members" => []})

      {:ok, invite_code, _} = Teamrc.Teams.create_team_with_invite(%{
        "name" => "Team All B",
        "members" => []
      })
      {:ok, _} = Teamrc.Teams.join_by_invite(invite_code, token)

      conn = get(conn, "/api/teams/all/#{token}")
      resp = json_response(conn, 200)

      assert is_list(resp["teams"])
      assert length(resp["teams"]) == 2
      names = Enum.map(resp["teams"], & &1["name"]) |> Enum.sort()
      assert names == ["Team All A", "Team All B"]
    end

    test "returns 404 for token with no teams", %{conn: conn} do
      token = "trc_ak_all_empty_#{:erlang.unique_integer([:positive])}"
      conn = get(conn, "/api/teams/all/#{token}")
      resp = json_response(conn, 404)
      assert resp["error"] == "not_found"
    end
  end

  describe "GET /api/teams/:token/head" do
    test "returns hashes for a valid token", %{conn: conn} do
      token = "trc_ak_head_api_#{:erlang.unique_integer([:positive])}"
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
      token = "trc_ak_head_match_#{:erlang.unique_integer([:positive])}"
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
      token = "trc_ak_conflict_api_#{:erlang.unique_integer([:positive])}"
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
      token = "trc_ak_ff_api_#{:erlang.unique_integer([:positive])}"
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
