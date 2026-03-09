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
      assert {:ok, _team_data} = Teams.put_team(pid, "tok_123", team)
      {:ok, result} = Teams.get_team(pid, "tok_123")
      assert result["name"] == "my-team"
      assert length(result["members"]) == 1
      assert hd(result["members"])["name"] == "agent1"
    end

    test "returns :error for unknown token", %{pid: pid} do
      assert :error = Teams.get_team(pid, "tok_unknown")
    end

    test "stores and retrieves knowledge", %{pid: pid} do
      team = %{"name" => "knowledge-team", "members" => [], "knowledge" => "shared notes here"}
      {:ok, _} = Teams.put_team(pid, "tok_k1", team)
      {:ok, result} = Teams.get_team(pid, "tok_k1")
      assert result["knowledge"] == "shared notes here"
    end

    test "updates knowledge on put_team overwrite", %{pid: pid} do
      Teams.put_team(pid, "tok_k2", %{"name" => "k-team", "members" => [], "knowledge" => "v1"})
      Teams.put_team(pid, "tok_k2", %{"name" => "k-team", "members" => [], "knowledge" => "v2"})
      {:ok, result} = Teams.get_team(pid, "tok_k2")
      assert result["knowledge"] == "v2"
    end

    test "get_team returns updated_at", %{pid: pid} do
      team = %{"name" => "ts-team", "members" => []}
      {:ok, _} = Teams.put_team(pid, "tok_ts", team)
      {:ok, result} = Teams.get_team(pid, "tok_ts")
      assert is_binary(result["updated_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(result["updated_at"])
    end
  end

  describe "put_team overwrite" do
    test "put_team overwrites existing team", %{pid: pid} do
      Teams.put_team(pid, "trc_ak_overwrite", %{"name" => "v1", "members" => []})
      Teams.put_team(pid, "trc_ak_overwrite", %{"name" => "v2", "members" => [%{"name" => "new", "role" => "test"}]})
      {:ok, team} = Teams.get_team(pid, "trc_ak_overwrite")
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
      assert :error = Teams.get_team(pid, "tok_preview_visitor")
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
      Teams.put_team(pid, token, %{"name" => "invite-team", "members" => []})

      {:ok, code, expires_at} = Teams.create_invite_from(pid, token, 24)
      assert String.starts_with?(code, "trc_inv_")
      assert %DateTime{} = expires_at
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "non-member returns :error", %{pid: pid} do
      assert :error = Teams.create_invite_from(pid, "tok_stranger", 24)
    end
  end
end
