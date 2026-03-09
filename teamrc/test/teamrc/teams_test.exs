defmodule Teamrc.TeamsTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Teamrc.Teams

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Teamrc.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    name = :"teams_#{:erlang.unique_integer([:positive])}"
    {:ok, teams_pid} = Teams.start_link(name: name)
    %{pid: teams_pid}
  end

  describe "put_team/get_team" do
    test "stores and retrieves a team", %{pid: pid} do
      team = %{"name" => "my-team", "members" => [%{"name" => "agent1", "role" => "worker"}]}
      assert {:ok, _team_data} = Teams.put_team_to(pid, "tok_123", team)
      {:ok, result} = Teams.get_team_from(pid, "tok_123")
      assert result["name"] == "my-team"
      assert length(result["members"]) == 1
      assert hd(result["members"])["name"] == "agent1"
    end

    test "returns :error for unknown token", %{pid: pid} do
      assert :error = Teams.get_team_from(pid, "tok_unknown")
    end

    test "stores and retrieves knowledge", %{pid: pid} do
      team = %{"name" => "knowledge-team", "members" => [], "knowledge" => "shared notes here"}
      {:ok, _} = Teams.put_team_to(pid, "tok_k1", team)
      {:ok, result} = Teams.get_team_from(pid, "tok_k1")
      assert result["knowledge"] == "shared notes here"
    end

    test "updates knowledge on put_team overwrite", %{pid: pid} do
      Teams.put_team_to(pid, "tok_k2", %{"name" => "k-team", "members" => [], "knowledge" => "v1"})
      Teams.put_team_to(pid, "tok_k2", %{"name" => "k-team", "members" => [], "knowledge" => "v2"})
      {:ok, result} = Teams.get_team_from(pid, "tok_k2")
      assert result["knowledge"] == "v2"
    end

    test "get_team returns updated_at", %{pid: pid} do
      team = %{"name" => "ts-team", "members" => []}
      {:ok, _} = Teams.put_team_to(pid, "tok_ts", team)
      {:ok, result} = Teams.get_team_from(pid, "tok_ts")
      assert is_binary(result["updated_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(result["updated_at"])
    end
  end

  describe "put_team overwrite" do
    test "put_team overwrites existing team", %{pid: pid} do
      Teams.put_team_to(pid, "trc_ak_overwrite", %{"name" => "v1", "members" => []})
      Teams.put_team_to(pid, "trc_ak_overwrite", %{"name" => "v2", "members" => [%{"name" => "new", "role" => "test"}]})
      {:ok, team} = Teams.get_team_from(pid, "trc_ak_overwrite")
      assert team["name"] == "v2"
      assert length(team["members"]) == 1
    end
  end

  describe "preview_by_invite" do
    test "returns team data without creating token_teams", %{pid: pid} do
      # Create a team with invite
      {:ok, invite_code, _team_id} = Teams.create_team_with_invite(pid, %{
        "name" => "preview-team",
        "members" => [%{"name" => "agent1", "role" => "dev"}]
      })

      # Preview should return team data
      {:ok, team} = Teams.preview_by_invite(pid, invite_code)
      assert team["name"] == "preview-team"
      assert length(team["members"]) == 1

      # A new token should NOT be able to get_team (no token_teams row created)
      assert :error = Teams.get_team_from(pid, "tok_preview_visitor")
    end

    test "returns :error with expired invite code", %{pid: pid} do
      # Insert an expired invite directly
      {:ok, invite_code, _team_id} = Teams.create_team_with_invite(pid, %{
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

      assert :error = Teams.preview_by_invite(pid, invite_code)
    end
  end

  describe "create_invite" do
    test "member can create a valid invite code", %{pid: pid} do
      token = "tok_inviter_#{:erlang.unique_integer([:positive])}"
      Teams.put_team_to(pid, token, %{"name" => "invite-team", "members" => []})

      {:ok, code, expires_at} = Teams.create_invite_from(pid, token, 24)
      assert String.starts_with?(code, "trc_inv_")
      assert %DateTime{} = expires_at
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "non-member returns :error", %{pid: pid} do
      assert :error = Teams.create_invite_from(pid, "tok_stranger", 24)
    end
  end

  describe "multi-team routing" do
    test "get_team with team_id returns the correct team", %{pid: pid} do
      token = "tok_multi_#{:erlang.unique_integer([:positive])}"

      # Create Team A via put_team
      {:ok, team_a} = Teams.put_team_to(pid, token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      # Create Team B via invite + join so the same token belongs to both
      {:ok, invite_code, _team_b_id} = Teams.create_team_with_invite(pid, %{
        "name" => "Team B",
        "members" => [%{"name" => "bot", "role" => "helper"}]
      })
      {:ok, team_b} = Teams.join_by_invite(pid, invite_code, token)
      team_b_id = team_b["id"]

      # With explicit team_id, get_team returns the requested team
      {:ok, got_a} = Teams.get_team_from(pid, token, team_a_id)
      assert got_a["name"] == "Team A"

      {:ok, got_b} = Teams.get_team_from(pid, token, team_b_id)
      assert got_b["name"] == "Team B"
    end

    test "put_team with team_id updates only the targeted team", %{pid: pid} do
      token = "tok_multi_put_#{:erlang.unique_integer([:positive])}"

      {:ok, team_a} = Teams.put_team_to(pid, token, %{"name" => "Team A", "members" => []})
      team_a_id = team_a["id"]

      {:ok, invite_code, _} = Teams.create_team_with_invite(pid, %{
        "name" => "Team B",
        "members" => []
      })
      {:ok, team_b} = Teams.join_by_invite(pid, invite_code, token)
      team_b_id = team_b["id"]

      # Update Team B by passing its ID
      {:ok, updated} = Teams.put_team_to(pid, token, %{
        "name" => "Team B Updated",
        "members" => [%{"name" => "new-agent", "role" => "dev"}]
      }, team_b_id)
      assert updated["name"] == "Team B Updated"

      # Team A should be unchanged
      {:ok, got_a} = Teams.get_team_from(pid, token, team_a_id)
      assert got_a["name"] == "Team A"
    end

    test "get_team with wrong team_id returns :error", %{pid: pid} do
      token = "tok_multi_err_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Teams.put_team_to(pid, token, %{"name" => "My Team", "members" => []})

      # A team_id the token doesn't belong to
      assert :error = Teams.get_team_from(pid, token, "00000000-0000-0000-0000-000000000000")
    end

    test "put_team with wrong team_id creates a new team instead of overwriting", %{pid: pid} do
      token = "tok_multi_new_#{:erlang.unique_integer([:positive])}"
      {:ok, team_a} = Teams.put_team_to(pid, token, %{"name" => "Team A", "members" => []})

      # Pass a team_id the token doesn't belong to — resolve_team_id returns nil, so it creates
      {:ok, team_new} = Teams.put_team_to(pid, token, %{
        "name" => "Team New",
        "members" => []
      }, "00000000-0000-0000-0000-000000000000")

      # Should have created a new team, not overwritten Team A
      assert team_new["name"] == "Team New"
      assert team_new["id"] != team_a["id"]

      {:ok, got_a} = Teams.get_team_from(pid, token, team_a["id"])
      assert got_a["name"] == "Team A"
    end
  end
end
