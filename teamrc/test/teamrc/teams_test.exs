defmodule Teamrc.TeamsTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Teamrc.Teams

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Teamrc.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "put_team/get_team" do
    test "stores and retrieves a team" do
      token = "tok_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "my-team", "members" => [%{"name" => "agent1", "role" => "worker"}]}
      assert {:ok, _team_data} = Teams.put_team(token, team)
      {:ok, result} = Teams.get_team(token)
      assert result["name"] == "my-team"
      assert length(result["members"]) == 1
      assert hd(result["members"])["name"] == "agent1"
    end

    test "returns :error for unknown token" do
      assert :error = Teams.get_team("tok_unknown_#{:erlang.unique_integer([:positive])}")
    end

    test "stores and retrieves knowledge" do
      token = "tok_k1_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "knowledge-team", "members" => [], "knowledge" => "shared notes here"}
      {:ok, _} = Teams.put_team(token, team)
      {:ok, result} = Teams.get_team(token)
      assert result["knowledge"] == "shared notes here"
    end

    test "knowledge is append-only on put_team overwrite" do
      token = "tok_k2_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "v1"})
      Teams.put_team(token, %{"name" => "k-team", "members" => [], "knowledge" => "v2"})
      {:ok, result} = Teams.get_team(token)
      assert result["knowledge"] =~ "v1"
      assert result["knowledge"] =~ "v2"
    end

    test "knowledge deduplicates identical lines" do
      token = "tok_k3_#{:erlang.unique_integer([:positive])}"
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
      token = "tok_ts_#{:erlang.unique_integer([:positive])}"
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
      {:ok, invite_code, _team_id} = Teams.create_team_with_invite(%{
        "name" => "preview-team",
        "members" => [%{"name" => "agent1", "role" => "dev"}]
      })

      {:ok, team} = Teams.preview_by_invite(invite_code)
      assert team["name"] == "preview-team"
      assert length(team["members"]) == 1

      # A new token should NOT be able to get_team (no token_teams row created)
      assert :error = Teams.get_team("tok_preview_visitor_#{:erlang.unique_integer([:positive])}")
    end

    test "returns :error with expired invite code" do
      {:ok, invite_code, _team_id} = Teams.create_team_with_invite(%{
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
      token = "tok_inviter_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(token, %{"name" => "invite-team", "members" => []})

      {:ok, code, expires_at} = Teams.create_invite(token, 24)
      assert String.starts_with?(code, "trc_inv_")
      assert %DateTime{} = expires_at
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "non-member returns :error" do
      assert :error = Teams.create_invite("tok_stranger_#{:erlang.unique_integer([:positive])}", 24)
    end
  end

  describe "multi-team routing" do
    test "get_team with team_id returns the correct team" do
      token = "tok_multi_#{:erlang.unique_integer([:positive])}"

      # Create Team A via put_team
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      # Create Team B via invite + join so the same token belongs to both
      {:ok, invite_code, _team_b_id} = Teams.create_team_with_invite(%{
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
      token = "tok_multi_put_#{:erlang.unique_integer([:positive])}"

      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      {:ok, invite_code, _} = Teams.create_team_with_invite(%{
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
      token = "tok_multi_err_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team(token, %{"name" => "My Team", "members" => []})

      # A team_id the token doesn't belong to
      assert :error = Teams.get_team(token, "00000000-0000-0000-0000-000000000000")
    end

    test "put_team with wrong team_id creates a new team instead of overwriting" do
      token = "tok_multi_new_#{:erlang.unique_integer([:positive])}"
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Team A", "members" => []})

      # Pass a team_id the token doesn't belong to — resolve_team_id returns nil, so it creates
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
      token = "tok_hash_create_#{:erlang.unique_integer([:positive])}"
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
      token = "tok_hash_change_#{:erlang.unique_integer([:positive])}"
      {:ok, v1} = Teams.put_team(token, %{"name" => "hash-team", "members" => [%{"name" => "alice", "role" => "dev"}]})
      {:ok, v2} = Teams.put_team(token, %{"name" => "hash-team", "members" => [%{"name" => "bob", "role" => "qa"}]})

      assert v1["hash"] != v2["hash"]
      assert v1["members_hash"] != v2["members_hash"]
      # Skills and knowledge didn't change
      assert v1["skills_hash"] == v2["skills_hash"]
    end

    test "hashes are consistent across get and put" do
      token = "tok_hash_consistent_#{:erlang.unique_integer([:positive])}"
      {:ok, created} = Teams.put_team(token, %{"name" => "consistent", "members" => []})
      {:ok, fetched} = Teams.get_team(token)

      assert created["hash"] == fetched["hash"]
      assert created["members_hash"] == fetched["members_hash"]
      assert created["skills_hash"] == fetched["skills_hash"]
      assert created["knowledge_hash"] == fetched["knowledge_hash"]
    end

    test "update without base_hash succeeds unconditionally (backward compat)" do
      token = "tok_hash_nobase_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team(token, %{"name" => "team", "members" => []})
      # Update without base_hash — should succeed even though hashes differ
      {:ok, result} = Teams.put_team(token, %{"name" => "updated", "members" => [%{"name" => "new", "role" => "dev"}]})
      assert result["name"] == "updated"
    end

    test "update with matching base_hash succeeds (fast-forward)" do
      token = "tok_hash_ff_#{:erlang.unique_integer([:positive])}"
      {:ok, v1} = Teams.put_team(token, %{"name" => "team", "members" => [%{"name" => "alice", "role" => "dev"}]})

      # Use the current hash as base_hash — should fast-forward
      {:ok, v2} = Teams.put_team(token, %{
        "name" => "team",
        "members" => [%{"name" => "alice", "role" => "dev"}, %{"name" => "bob", "role" => "qa"}],
        "base_hash" => v1["hash"]
      })

      assert length(v2["members"]) == 2
      assert v2["hash"] != v1["hash"]
    end

    test "update with mismatched base_hash on members returns conflict" do
      token = "tok_hash_conflict_#{:erlang.unique_integer([:positive])}"
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
      token = "tok_hash_merge_#{:erlang.unique_integer([:positive])}"
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
      token = "tok_head_#{:erlang.unique_integer([:positive])}"
      {:ok, created} = Teams.put_team(token, %{"name" => "head-team", "members" => []})

      {:ok, hashes} = Teams.get_team_hashes(token)
      assert hashes["hash"] == created["hash"]
      assert hashes["members_hash"] == created["members_hash"]
      assert hashes["skills_hash"] == created["skills_hash"]
      assert hashes["knowledge_hash"] == created["knowledge_hash"]
    end

    test "returns :error for unknown token" do
      assert :error = Teams.get_team_hashes("tok_head_unknown_#{:erlang.unique_integer([:positive])}")
    end

    test "returns hashes for specific team_id" do
      token = "tok_head_multi_#{:erlang.unique_integer([:positive])}"
      {:ok, team_a} = Teams.put_team(token, %{"name" => "Head A", "members" => []})

      {:ok, hashes} = Teams.get_team_hashes(token, team_a["id"])
      assert hashes["hash"] == team_a["hash"]
    end
  end
end
