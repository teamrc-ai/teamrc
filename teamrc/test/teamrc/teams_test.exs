defmodule Teamrc.TeamsTest do
  use Teamrc.DataCase, async: false

  alias Teamrc.Teams
  import Teamrc.AccountsFixtures

  describe "put_team/get_team" do
    test "stores and retrieves a team" do
      token = "trc_ak_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "my-team", "members" => [%{"name" => "agent1", "role" => "worker"}]}
      assert {:ok, _team_data} = Teams.put_team(token, team)
      {:ok, result} = Teams.get_team(token)
      assert result["name"] == "my-team"
      assert length(result["members"]) == 1
      assert hd(result["members"])["name"] == "agent1"
    end

    test "returns :error for unknown token" do
      assert :error = Teams.get_team("trc_ak_unknown_#{:erlang.unique_integer([:positive])}")
    end

    test "stores and retrieves knowledge" do
      token = "trc_ak_k1_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "knowledge-team", "members" => [], "knowledge" => "shared notes here"}
      {:ok, _} = Teams.put_team(token, team)
      {:ok, result} = Teams.get_team(token)
      assert result["knowledge"] == "shared notes here"
    end

    test "knowledge is append-only on put_team overwrite" do
      token = "trc_ak_k2_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "v1"})
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "v2"})
      {:ok, result} = Teams.get_team(token)
      assert result["knowledge"] =~ "v1"
      assert result["knowledge"] =~ "v2"
    end

    test "knowledge deduplicates identical lines" do
      token = "trc_ak_k3_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "line A\nline B"})
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "line B\nline C"})
      {:ok, result} = Teams.get_team(token)
      assert result["knowledge"] =~ "line A"
      assert result["knowledge"] =~ "line B"
      assert result["knowledge"] =~ "line C"
      count = result["knowledge"] |> String.split("\n") |> Enum.count(&(&1 =~ "line B"))
      assert count == 1
    end

    test "get_team returns content hashes" do
      token = "trc_ak_ts_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "ts-team", "members" => []}
      {:ok, _} = Teams.put_team(token, team)
      {:ok, result} = Teams.get_team(token)
      assert is_binary(result["hash"])
      assert is_binary(result["members_hash"])
      assert is_binary(result["skills_hash"])
      assert is_binary(result["knowledge_hash"])
      assert String.length(result["hash"]) == 64
    end
  end

  describe "put_team overwrite" do
    test "put_team overwrites existing team" do
      token = "trc_ak_overwrite_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "v1", "members" => []})
      Teams.put_team(token, %{"name" => "v2", "members" => [%{"name" => "new", "role" => "test"}]})
      {:ok, team} = Teams.get_team(token)
      assert team["name"] == "v2"
      assert length(team["members"]) == 1
    end
  end

  describe "preview_by_invite" do
    test "returns team data without creating token_teams" do
      {:ok, invite_code, _team_id, _} = Teams.create_team_with_invite(%{
        "name" => "preview-team",
        "members" => [%{"name" => "agent1", "role" => "dev", "soul" => "I am a dev agent"}],
        "knowledge" => "secret knowledge"
      })

      {:ok, team} = Teams.preview_by_invite(invite_code)
      assert team["name"] == "preview-team"
      assert length(team["members"]) == 1

      # Knowledge should be redacted from preview
      assert is_nil(team["knowledge"])

      # Member souls should be redacted from preview
      Enum.each(team["members"], fn member ->
        refute Map.has_key?(member, "soul")
      end)

      # A new token should NOT be able to get_team (no token_teams row created)
      assert :error = Teams.get_team("trc_ak_preview_visitor_#{:erlang.unique_integer([:positive])}")
    end

    test "returns :error with expired invite code" do
      {:ok, invite_code, _team_id, _} = Teams.create_team_with_invite(%{
        "name" => "expired-team",
        "members" => []
      })

      # Expire the invite by updating it in the DB
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -3600)

      Teamrc.Repo.update_all(
        from(i in Teamrc.Schema.Invite, where: i.code == ^invite_code),
        set: [expires_at: past]
      )

      assert :error = Teams.preview_by_invite(invite_code)
    end
  end

  describe "create_invite" do
    test "member can create a valid invite code" do
      token = "trc_ak_inviter_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "invite-team", "members" => []})

      {:ok, code, expires_at} = Teams.create_invite(token, 24)
      assert String.starts_with?(code, "trc_inv_")
      assert %DateTime{} = expires_at
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "non-member returns :error" do
      assert :error = Teams.create_invite("trc_ak_stranger_#{:erlang.unique_integer([:positive])}", 24)
    end
  end

  describe "multi-team routing" do
    test "get_team with team_id returns the correct team" do
      token = "trc_ak_multi_#{:erlang.unique_integer([:positive])}"

      # Create Team A via put_team
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      # Create Team B via invite + join so the same token belongs to both
      {:ok, invite_code, _team_b_id, _} = Teams.create_team_with_invite(%{
        "name" => "Team B",
        "members" => [%{"name" => "bot", "role" => "helper"}]
      })
      {:ok, team_b} = Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # With explicit team_id, get_team returns the requested team
      {:ok, got_a} = Teams.get_team(token, team_a_id)
      assert got_a["name"] == "Team A"

      {:ok, got_b} = Teams.get_team(token, team_b_id)
      assert got_b["name"] == "Team B"
    end

    test "put_team with team_id updates only the targeted team" do
      token = "trc_ak_multi_put_#{:erlang.unique_integer([:positive])}"

      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      {:ok, invite_code, _, _} = Teams.create_team_with_invite(%{
        "name" => "Team B",
        "members" => []
      })
      {:ok, team_b} = Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # Update Team B by passing its ID
      {:ok, updated} = Teams.put_team(token, %{
        "name" => "Team B Updated",
        "members" => [%{"name" => "new-agent", "role" => "dev"}]
      }, team_b_id)
      assert updated["name"] == "Team B Updated"

      # Team A should be unchanged
      {:ok, got_a} = Teams.get_team(token, team_a_id)
      assert got_a["name"] == "Team A"
    end

    test "get_team with wrong team_id returns :error" do
      token = "trc_ak_multi_err_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team(token, %{"name" => "My Team", "members" => []})

      # A team_id the token doesn't belong to
      assert :error = Teams.get_team(token, "00000000-0000-0000-0000-000000000000")
    end

    test "put_team with wrong team_id creates a new team instead of overwriting" do
      token = "trc_ak_multi_new_#{:erlang.unique_integer([:positive])}"
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})

      # Pass a team_id the token doesn't belong to. resolve_team_id returns nil, so it creates
      {:ok, team_new} = Teams.put_team(token, %{
        "name" => "Team New",
        "members" => []
      }, "00000000-0000-0000-0000-000000000000")

      # Should have created a new team, not overwritten Team A
      assert team_new["name"] == "Team New"
      assert team_new["id"] != team_a["id"]

      {:ok, got_a} = Teams.get_team(token, team_a["id"])
      assert got_a["name"] == "Team A"
    end
  end

  describe "content hashes" do
    test "hashes are stamped on create" do
      token = "trc_ak_hash_create_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "hash-team", "members" => [%{"name" => "alice", "role" => "dev"}], "knowledge" => "notes\n"}
      {:ok, result} = Teams.put_team(token, team)

      assert is_binary(result["hash"])
      assert is_binary(result["members_hash"])
      assert is_binary(result["skills_hash"])
      assert is_binary(result["knowledge_hash"])
      assert String.length(result["hash"]) == 64
      assert String.length(result["members_hash"]) == 64
    end

    test "hashes change when team content changes" do
      token = "trc_ak_hash_change_#{:erlang.unique_integer([:positive])}"
      {:ok, v1} = Teams.put_team(token, %{"name" => "hash-team", "members" => [%{"name" => "alice", "role" => "dev"}]})
      {:ok, v2} = Teams.put_team(token, %{"name" => "hash-team", "members" => [%{"name" => "bob", "role" => "qa"}]})

      assert v1["hash"] != v2["hash"]
      assert v1["members_hash"] != v2["members_hash"]
      # Skills and knowledge didn't change
      assert v1["skills_hash"] == v2["skills_hash"]
    end

    test "hashes are consistent across get and put" do
      token = "trc_ak_hash_consistent_#{:erlang.unique_integer([:positive])}"
      {:ok, created} = Teams.put_team(token, %{"name" => "consistent", "members" => []})
      {:ok, fetched} = Teams.get_team(token)

      assert created["hash"] == fetched["hash"]
      assert created["members_hash"] == fetched["members_hash"]
      assert created["skills_hash"] == fetched["skills_hash"]
      assert created["knowledge_hash"] == fetched["knowledge_hash"]
    end

    test "update without base_hash succeeds unconditionally (backward compat)" do
      token = "trc_ak_hash_nobase_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team(token, %{"name" => "team", "members" => []})
      # Update without base_hash. Should succeed even though hashes differ
      {:ok, result} = Teams.put_team(token, %{"name" => "updated", "members" => [%{"name" => "new", "role" => "dev"}]})
      assert result["name"] == "updated"
    end

    test "update with matching base_hash succeeds (fast-forward)" do
      token = "trc_ak_hash_ff_#{:erlang.unique_integer([:positive])}"
      {:ok, v1} = Teams.put_team(token, %{"name" => "team", "members" => [%{"name" => "alice", "role" => "dev"}]})

      # Use the current hash as base_hash. Should fast-forward
      {:ok, v2} = Teams.put_team(token, %{
        "name" => "team",
        "members" => [%{"name" => "alice", "role" => "dev"}, %{"name" => "bob", "role" => "qa"}],
        "base_hash" => v1["hash"]
      })

      assert length(v2["members"]) == 2
      assert v2["hash"] != v1["hash"]
    end

    test "update with mismatched base_hash on members returns conflict" do
      token = "trc_ak_hash_conflict_#{:erlang.unique_integer([:positive])}"
      {:ok, _v1} = Teams.put_team(token, %{"name" => "team", "members" => [%{"name" => "alice", "role" => "dev"}]})

      # Simulate a stale base_hash
      result = Teams.put_team(token, %{
        "name" => "team",
        "members" => [%{"name" => "charlie", "role" => "ops"}],
        "base_hash" => "0000000000000000000000000000000000000000000000000000000000000000"
      })

      assert {:error, :conflict, hashes} = result
      assert is_binary(hashes.hash)
      assert is_binary(hashes.members_hash)
    end

    test "update with knowledge-only difference performs server-side merge" do
      token = "trc_ak_hash_merge_#{:erlang.unique_integer([:positive])}"
      {:ok, v1} = Teams.put_team(token, %{
        "name" => "team",
        "members" => [],
        "knowledge" => "line1\n"
      })

      # Another client updates knowledge on the server
      {:ok, _v2} = Teams.put_team(token, %{
        "name" => "team",
        "members" => [],
        "knowledge" => "line1\nline2\n"
      })

      # Now original client tries to push with stale base_hash but same members/skills
      # and different knowledge
      {:ok, v3} = Teams.put_team(token, %{
        "name" => "team",
        "members" => [],
        "knowledge" => "line1\nline3\n",
        "base_hash" => v1["hash"]
      })

      # Should have merged knowledge: line1, line2, line3
      assert String.contains?(v3["knowledge"], "line1")
      assert String.contains?(v3["knowledge"], "line2")
      assert String.contains?(v3["knowledge"], "line3")
    end
  end

  describe "get_team_hashes" do
    test "returns hashes for a valid token" do
      token = "trc_ak_head_#{:erlang.unique_integer([:positive])}"
      {:ok, created} = Teams.put_team(token, %{"name" => "head-team", "members" => []})

      {:ok, hashes} = Teams.get_team_hashes(token)
      assert hashes["hash"] == created["hash"]
      assert hashes["members_hash"] == created["members_hash"]
      assert hashes["skills_hash"] == created["skills_hash"]
      assert hashes["knowledge_hash"] == created["knowledge_hash"]
    end

    test "returns :error for unknown token" do
      assert :error = Teams.get_team_hashes("trc_ak_head_unknown_#{:erlang.unique_integer([:positive])}")
    end

    test "returns hashes for specific team_id" do
      token = "trc_ak_head_multi_#{:erlang.unique_integer([:positive])}"
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Head A", "members" => []})

      {:ok, hashes} = Teams.get_team_hashes(token, team_a["id"])
      assert hashes["hash"] == team_a["hash"]
    end
  end

  describe "join_by_invite" do
    test "happy path: create team, create invite, join with another token" do
      creator_token = "trc_ak_join_creator_#{:erlang.unique_integer([:positive])}"
      joiner_token = "trc_ak_join_joiner_#{:erlang.unique_integer([:positive])}"

      {:ok, _team} = Teams.put_team(creator_token, %{
        "name" => "join-team",
        "members" => [%{"name" => "bot", "role" => "helper"}]
      })

      {:ok, code, _expires} = Teams.create_invite(creator_token, 24)
      {:ok, joined_team} = Teams.join_by_invite(code, joiner_token)

      assert joined_team["name"] == "join-team"
      assert length(joined_team["members"]) == 1

      # Joiner can now get the team
      {:ok, fetched} = Teams.get_team(joiner_token)
      assert fetched["name"] == "join-team"
    end

    test "expired invite returns :error" do
      {:ok, invite_code, _team_id, _} = Teams.create_team_with_invite(%{
        "name" => "expired-join-team",
        "members" => []
      })

      # Expire the invite
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -3600)

      Repo.update_all(
        from(i in Teamrc.Schema.Invite, where: i.code == ^invite_code),
        set: [expires_at: past]
      )

      token = "trc_ak_join_expired_#{:erlang.unique_integer([:positive])}"
      assert :error = Teams.join_by_invite(invite_code, token)
    end

    test "invalid/nonexistent invite code returns :error" do
      token = "trc_ak_join_invalid_#{:erlang.unique_integer([:positive])}"
      assert :error = Teams.join_by_invite("trc_inv_nonexistent_code", token)
    end

    test "joining same team twice is idempotent" do
      creator_token = "trc_ak_join_idem_cr_#{:erlang.unique_integer([:positive])}"
      joiner_token = "trc_ak_join_idem_jr_#{:erlang.unique_integer([:positive])}"

      {:ok, _team} = Teams.put_team(creator_token, %{
        "name" => "idem-team",
        "members" => []
      })

      {:ok, code, _expires} = Teams.create_invite(creator_token, 24)

      {:ok, first_join} = Teams.join_by_invite(code, joiner_token)
      {:ok, second_join} = Teams.join_by_invite(code, joiner_token)

      assert first_join["id"] == second_join["id"]
      assert first_join["name"] == second_join["name"]
    end
  end

  describe "preview_by_clone_token" do
    setup do
      alias Teamrc.Accounts

      token = "trc_ak_clone_prev_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{
        "name" => "clone-preview-team",
        "members" => [%{"name" => "dev", "role" => "backend"}],
        "knowledge" => "private knowledge"
      })
      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Create user and link token
      {:ok, user} = Accounts.register_user(%{
        "email" => "clone_preview_#{:erlang.unique_integer([:positive])}@test.com",
        "terms_accepted" => "true"
      })
      {:ok, _mt} = Accounts.link_machine_token(user.id, token, "test-machine")

      # Claim ownership so we can set visibility
      {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      %{token: token, team_id: team_id, team_data: team_data}
    end

    test "public team clone token returns team data", %{token: token, team_id: team_id} do
      {:ok, updated} = Teams.set_visibility(token, team_id, "public")
      clone_token = updated.clone_token

      {:ok, preview} = Teams.preview_by_clone_token(clone_token)
      assert preview["name"] == "clone-preview-team"
      assert length(preview["members"]) == 1

      # Knowledge should be redacted from clone preview
      assert is_nil(preview["knowledge"])
    end

    test "private team clone token returns :error", %{token: token, team_id: team_id} do
      # Set public first to generate clone_token, then back to private
      {:ok, updated} = Teams.set_visibility(token, team_id, "public")
      clone_token = updated.clone_token

      {:ok, _} = Teams.set_visibility(token, team_id, "private")
      assert :error = Teams.preview_by_clone_token(clone_token)
    end

    test "invalid clone token returns :error" do
      assert :error = Teams.preview_by_clone_token("trc_cl_nonexistent_token")
    end
  end

  describe "erase_token" do
    test "erases all token_teams for a token" do
      token = "trc_ak_erase_ctx_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team(token, %{"name" => "Erase Team", "members" => []})

      {:ok, count} = Teams.erase_token(token)
      assert count >= 1

      assert :error = Teams.get_teams(token)
    end

    test "erases only specific team when team_id is given" do
      token = "trc_ak_erase_scoped_#{:erlang.unique_integer([:positive])}"

      {:ok, team_a} = Teams.put_team(token, %{"name" => "Keep Team", "members" => []})
      team_a_id = team_a["id"]

      {:ok, invite_code, _, _} = Teams.create_team_with_invite(%{
        "name" => "Remove Team",
        "members" => []
      })
      {:ok, team_b} = Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # Erase only team_b
      {:ok, count} = Teams.erase_token(token, team_b_id)
      assert count == 1

      # Team A should still be accessible
      {:ok, got_a} = Teams.get_team(token, team_a_id)
      assert got_a["name"] == "Keep Team"

      # Team B should not be accessible
      assert :error = Teams.get_team(token, team_b_id)
    end

    test "returns 0 when no teams to erase" do
      token = "trc_ak_erase_empty_ctx_#{:erlang.unique_integer([:positive])}"
      {:ok, count} = Teams.erase_token(token)
      assert count == 0
    end
  end

  describe "claim_ownership_by_user" do
    defp make_participant(user, team_id) do
      token = "trc_ak_claim_#{:erlang.unique_integer([:positive])}"
      {:ok, _mt} = Teamrc.Accounts.link_machine_token(user.id, token, "claim-machine")
      {:ok, invite_code, _expires} = Teams.create_invite_by_team_id(team_id, 24)
      Teams.join_by_invite(invite_code, token)
    end

    test "claims ownership with valid secret" do
      team_attrs = %{
        name: "claim-web",
        members: [%{name: "dev", role: "dev"}],
        skills: [],
        platforms: []
      }
      {:ok, _invite, team_id, claim_secret} = Teams.create_team_with_invite(team_attrs)

      user = user_fixture()
      make_participant(user, team_id)
      assert {:ok, :claimed} = Teams.claim_ownership_by_user(user.id, team_id, claim_secret)

      team = Teamrc.Repo.get!(Teamrc.Schema.Team, team_id)
      assert team.owner_user_id == user.id
      assert is_nil(team.owner_claim_secret)
    end

    test "rejects invalid secret" do
      team_attrs = %{
        name: "claim-reject",
        members: [%{name: "dev", role: "dev"}],
        skills: [],
        platforms: []
      }
      {:ok, _invite, team_id, _claim_secret} = Teams.create_team_with_invite(team_attrs)

      user = user_fixture()
      make_participant(user, team_id)
      assert {:error, :invalid_secret} = Teams.claim_ownership_by_user(user.id, team_id, "trc_ocs_wrong")

      team = Teamrc.Repo.get!(Teamrc.Schema.Team, team_id)
      assert is_nil(team.owner_user_id)
    end

    test "rejects non-participant" do
      team_attrs = %{
        name: "claim-nopart",
        members: [%{name: "dev", role: "dev"}],
        skills: [],
        platforms: []
      }
      {:ok, _invite, team_id, claim_secret} = Teams.create_team_with_invite(team_attrs)

      user = user_fixture()
      # User is NOT a participant — no machine token linked to this team
      assert {:error, :not_participant} = Teams.claim_ownership_by_user(user.id, team_id, claim_secret)

      team = Teamrc.Repo.get!(Teamrc.Schema.Team, team_id)
      assert is_nil(team.owner_user_id)
    end

    test "rejects claim for already-owned team" do
      owner = user_fixture()
      team_attrs = %{
        name: "claim-owned",
        members: [%{name: "dev", role: "dev"}],
        skills: [],
        platforms: []
      }
      {:ok, _invite, team_id, claim_secret} = Teams.create_team_with_invite(team_attrs, owner_user_id: owner.id)

      other_user = user_fixture()
      make_participant(other_user, team_id)
      assert {:error, :invalid_secret} = Teams.claim_ownership_by_user(other_user.id, team_id, claim_secret)
    end
  end

  describe "delete_team" do
    setup do
      owner = user_fixture()
      token = "trc_ak_delete_#{:erlang.unique_integer([:positive])}"

      team_attrs = %{
        name: "team-to-delete",
        members: [
          %{name: "lead", role: "Team lead", soul: "You are the team lead with deep expertise."},
          %{name: "dev", role: "Developer", soul: "You write clean code.", skills: ["testing", "review"]}
        ],
        skills: [
          %{"id" => "testing", "name" => "Testing", "body" => "Write comprehensive tests."},
          %{"id" => "review", "name" => "Code Review", "body" => "Review PRs carefully."}
        ],
        platforms: ["claude-code", "cursor"],
        knowledge: "This team works on the billing service. The main database is PostgreSQL."
      }

      {:ok, _invite, team_id, _secret} =
        Teams.create_team_with_invite(team_attrs, owner_user_id: owner.id)

      # Connect a machine token
      {:ok, _} = Teamrc.Repo.insert(%Teamrc.Schema.TokenTeam{token: token, team_id: team_id})

      # Create an invite
      {:ok, _code, _expires} = Teams.create_invite_by_team_id(team_id, 24)

      %{owner: owner, token: token, team_id: team_id}
    end

    test "anonymizes team skills, knowledge, and platforms", %{owner: owner, team_id: team_id} do
      assert :ok = Teams.delete_team(team_id, owner.id)

      team = Teamrc.Repo.get(Teamrc.Schema.Team, team_id)
      assert team.deleted_at != nil
      assert team.name == "team-to-delete"
      assert team.skills == []
      assert team.knowledge == nil
      assert team.platforms == []
      assert team.visibility == "private"
      assert team.clone_token == nil
      assert team.owner_user_id == nil
      assert team.owner_claim_secret == nil
      assert team.members_hash == nil
      assert team.skills_hash == nil
      assert team.knowledge_hash == nil
    end

    test "preserves member names and roles but clears souls and skills", %{owner: owner, team_id: team_id} do
      assert :ok = Teams.delete_team(team_id, owner.id)

      members =
        Ecto.Query.from(m in Teamrc.Schema.Member, where: m.team_id == ^team_id, order_by: m.name)
        |> Teamrc.Repo.all()

      assert length(members) == 2

      [dev, lead] = members
      assert dev.name == "dev"
      assert dev.role == "Developer"
      assert dev.soul == nil
      assert dev.skills == []

      assert lead.name == "lead"
      assert lead.role == "Team lead"
      assert lead.soul == nil
      assert lead.skills == []
    end

    test "disconnects all machines and revokes all invites", %{owner: owner, token: token, team_id: team_id} do
      # Verify they exist before delete
      assert Teamrc.Repo.exists?(Ecto.Query.from(tt in Teamrc.Schema.TokenTeam, where: tt.token == ^token))
      assert Teamrc.Repo.exists?(Ecto.Query.from(i in Teamrc.Schema.Invite, where: i.team_id == ^team_id))

      assert :ok = Teams.delete_team(team_id, owner.id)

      assert Teamrc.Repo.all(Ecto.Query.from(tt in Teamrc.Schema.TokenTeam, where: tt.team_id == ^team_id)) == []
      assert Teamrc.Repo.all(Ecto.Query.from(i in Teamrc.Schema.Invite, where: i.team_id == ^team_id)) == []
    end

    test "deleted team is invisible to all query functions", %{owner: owner, token: token, team_id: team_id} do
      assert :ok = Teams.delete_team(team_id, owner.id)

      assert Teams.get_team_by_id(team_id) == nil
      assert Teams.get_team(token, team_id) == :error
      assert Teams.get_teams(token) == :error
    end

    test "double-delete returns not_found", %{owner: owner, team_id: team_id} do
      assert :ok = Teams.delete_team(team_id, owner.id)
      assert {:error, :not_found} = Teams.delete_team(team_id, owner.id)
    end

    test "returns error for non-existent team" do
      assert {:error, :not_found} = Teams.delete_team(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "non-owner cannot delete team", %{team_id: team_id} do
      other_user = user_fixture()
      assert {:error, :not_authorized} = Teams.delete_team(team_id, other_user.id)

      # Team should still be fully intact
      team = Teams.get_team_by_id(team_id)
      assert team != nil
      assert length(team.members) == 2
    end
  end

  describe "web mutations recompute content hashes (BUG 1)" do
    setup do
      token = "trc_ak_webhash_#{:erlang.unique_integer([:positive])}"

      {:ok, team_data} =
        Teams.put_team(token, %{
          "name" => "web-hash-team",
          "members" => [%{"name" => "alice", "role" => "dev"}],
          "skills" => [%{"id" => "skill-a", "body" => "do stuff"}],
          "knowledge" => "initial knowledge"
        })

      team = Teams.get_team_by_id(team_data["id"])

      {:ok, initial_hashes} = Teams.get_team_hashes(token, team_data["id"])

      %{token: token, team: team, team_id: team_data["id"], initial_hashes: initial_hashes}
    end

    test "add_member updates hashes", %{token: token, team_id: team_id, initial_hashes: initial_hashes} do
      {:ok, _member} = Teams.add_member(team_id, %{name: "bob", role: "qa"})

      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert new_hashes["members_hash"] != initial_hashes["members_hash"]
      assert new_hashes["hash"] != initial_hashes["hash"]
      # Skills and knowledge unchanged
      assert new_hashes["skills_hash"] == initial_hashes["skills_hash"]
      assert new_hashes["knowledge_hash"] == initial_hashes["knowledge_hash"]
    end

    test "update_member updates hashes", %{token: token, team: team, team_id: team_id, initial_hashes: initial_hashes} do
      member = hd(team.members)
      {:ok, _updated} = Teams.update_member(member, %{role: "lead"})

      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert new_hashes["members_hash"] != initial_hashes["members_hash"]
      assert new_hashes["hash"] != initial_hashes["hash"]
    end

    test "delete_member updates hashes", %{token: token, team: team, team_id: team_id, initial_hashes: initial_hashes} do
      member = hd(team.members)
      {:ok, _deleted} = Teams.delete_member(member)

      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert new_hashes["members_hash"] != initial_hashes["members_hash"]
      assert new_hashes["hash"] != initial_hashes["hash"]
    end

    test "update_team_skills updates hashes", %{token: token, team: team, team_id: team_id, initial_hashes: initial_hashes} do
      new_skills = [%{"id" => "skill-b", "body" => "new stuff"}]
      {:ok, _updated} = Teams.update_team_skills(team, new_skills)

      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert new_hashes["skills_hash"] != initial_hashes["skills_hash"]
      assert new_hashes["hash"] != initial_hashes["hash"]
      # Members unchanged
      assert new_hashes["members_hash"] == initial_hashes["members_hash"]
    end

    test "update_team_name updates stored hashes", %{token: token, team: team, team_id: team_id} do
      {:ok, _updated} = Teams.update_team_name(team, "renamed-team")

      # Name doesn't affect content hashes (members/skills/knowledge), but recompute should still run
      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert is_binary(new_hashes["hash"])
      assert String.length(new_hashes["hash"]) == 64
    end

    test "delete_skill updates hashes", %{token: token, team: team, team_id: team_id, initial_hashes: initial_hashes} do
      {:ok, _updated} = Teams.delete_skill(team, "skill-a")

      {:ok, new_hashes} = Teams.get_team_hashes(token, team_id)
      assert new_hashes["skills_hash"] != initial_hashes["skills_hash"]
      assert new_hashes["hash"] != initial_hashes["hash"]
    end

    test "web edit followed by CLI get_team returns consistent data", %{token: token, team_id: team_id} do
      {:ok, _member} = Teams.add_member(team_id, %{name: "charlie", role: "ops"})

      {:ok, team_map} = Teams.get_team(token, team_id)
      {:ok, stored_hashes} = Teams.get_team_hashes(token, team_id)

      # The hashes from get_team (computed on the fly) should match the stored hashes
      assert team_map["members_hash"] == stored_hashes["members_hash"]
      assert team_map["skills_hash"] == stored_hashes["skills_hash"]
      assert team_map["knowledge_hash"] == stored_hashes["knowledge_hash"]
      assert team_map["hash"] == stored_hashes["hash"]
    end
  end

  describe "create_invite_by_team_id (BUG 2)" do
    test "creates invite without a token" do
      {:ok, _invite_code, team_id, _} =
        Teams.create_team_with_invite(%{"name" => "web-only-team", "members" => []})

      {:ok, code, expires_at} = Teams.create_invite_by_team_id(team_id, 24)
      assert String.starts_with?(code, "trc_inv_")
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "web-only owner can generate invite for their team" do
      # Create a user for the owner
      user = user_fixture()

      # Create a team via web wizard (no machine token, direct owner_user_id)
      {:ok, _invite_code, team_id, _} =
        Teams.create_team_with_invite(
          %{"name" => "web-owner-team", "members" => []},
          owner_user_id: user.id
        )

      {:ok, code, _expires_at} = Teams.create_invite_by_team_id(team_id, 48)
      assert String.starts_with?(code, "trc_inv_")

      # The invite can be used to join
      joiner_token = "trc_ak_joiner_#{:erlang.unique_integer([:positive])}"
      {:ok, joined} = Teams.join_by_invite(code, joiner_token)
      assert joined["name"] == "web-owner-team"
    end
  end

  describe "set_visibility_by_owner (BUG 3)" do
    test "web-only owner can toggle visibility" do
      user = user_fixture()

      {:ok, _invite_code, team_id, _} =
        Teams.create_team_with_invite(
          %{"name" => "visibility-team", "members" => []},
          owner_user_id: user.id
        )

      {:ok, updated} = Teams.set_visibility_by_owner(user.id, team_id, "public")
      assert updated.visibility == "public"
      assert is_binary(updated.clone_token)

      {:ok, private_again} = Teams.set_visibility_by_owner(user.id, team_id, "private")
      assert private_again.visibility == "private"
    end

    test "non-owner cannot set visibility" do
      user = user_fixture()
      other_user = user_fixture()

      {:ok, _invite_code, team_id, _} =
        Teams.create_team_with_invite(
          %{"name" => "owned-team", "members" => []},
          owner_user_id: user.id
        )

      assert {:error, :not_owner} = Teams.set_visibility_by_owner(other_user.id, team_id, "public")
    end

    test "returns error for invalid visibility" do
      assert {:error, :invalid_visibility} = Teams.set_visibility_by_owner(Ecto.UUID.generate(), Ecto.UUID.generate(), "bogus")
    end
  end

  describe "diff-based member updates" do
    test "unchanged members keep stable IDs" do
      token = "trc_ak_diff1_#{:erlang.unique_integer([:positive])}"

      Teams.put_team(token, %{
        "name" => "stable-team",
        "members" => [
          %{"name" => "alice", "role" => "frontend"},
          %{"name" => "bob", "role" => "backend"}
        ]
      })

      {:ok, first} = Teams.get_team(token)
      first_ids = first["members"] |> Enum.map(& &1["name"]) |> Enum.sort()

      # Update only bob's role — alice should keep stable ID
      Teams.put_team(token, %{
        "name" => "stable-team",
        "members" => [
          %{"name" => "alice", "role" => "frontend"},
          %{"name" => "bob", "role" => "senior backend"}
        ]
      })

      {:ok, second} = Teams.get_team(token)
      second_ids = second["members"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert first_ids == second_ids
    end

    test "adding a member does not delete existing ones" do
      token = "trc_ak_diff2_#{:erlang.unique_integer([:positive])}"

      Teams.put_team(token, %{
        "name" => "grow-team",
        "members" => [%{"name" => "alice", "role" => "frontend"}]
      })

      Teams.put_team(token, %{
        "name" => "grow-team",
        "members" => [
          %{"name" => "alice", "role" => "frontend"},
          %{"name" => "charlie", "role" => "devops"}
        ]
      })

      {:ok, result} = Teams.get_team(token)
      names = result["members"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == ["alice", "charlie"]
    end

    test "removing a member only deletes that member" do
      token = "trc_ak_diff3_#{:erlang.unique_integer([:positive])}"

      Teams.put_team(token, %{
        "name" => "shrink-team",
        "members" => [
          %{"name" => "alice", "role" => "frontend"},
          %{"name" => "bob", "role" => "backend"}
        ]
      })

      Teams.put_team(token, %{
        "name" => "shrink-team",
        "members" => [%{"name" => "alice", "role" => "frontend"}]
      })

      {:ok, result} = Teams.get_team(token)
      assert length(result["members"]) == 1
      assert hd(result["members"])["name"] == "alice"
    end
  end
end
