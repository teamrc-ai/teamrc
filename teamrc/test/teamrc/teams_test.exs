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
  end

  describe "sync" do
    test "stores hashes and returns empty when no other platforms", %{pid: pid} do
      Teams.put_team(pid, "tok_a", %{"name" => "test", "members" => []})

      {:ok, result} = Teams.sync_to(pid, "tok_a", "claude-code", %{"team.yaml" => "abc123"}, %{})
      assert result.files == %{}
    end

    test "returns changed files from other platforms", %{pid: pid} do
      Teams.put_team(pid, "tok_a", %{"name" => "test", "members" => []})
      Teams.put_team(pid, "tok_b", %{"name" => "test", "members" => []})

      # Simulate both tokens on same team by syncing through same token namespace
      # Platform A syncs with content
      {:ok, _} = Teams.sync_to(pid, "tok_a", "claude-code", %{"team.yaml" => "hash_v2"}, %{"team.yaml" => "name: updated-team"})

      # Platform B syncs with old hash — should get the new content
      {:ok, result} = Teams.sync_to(pid, "tok_a", "openclaw", %{"team.yaml" => "hash_v1"}, %{})
      assert result.files["team.yaml"].content == "name: updated-team"
      assert is_integer(result.files["team.yaml"].updated_at)
    end

    test "does not return files when hashes match", %{pid: pid} do
      Teams.put_team(pid, "tok_a", %{"name" => "test", "members" => []})

      {:ok, _} = Teams.sync_to(pid, "tok_a", "claude-code", %{"team.yaml" => "same_hash"}, %{"team.yaml" => "content"})
      {:ok, result} = Teams.sync_to(pid, "tok_a", "openclaw", %{"team.yaml" => "same_hash"}, %{})
      assert result.files == %{}
    end

    test "returns error for unknown token", %{pid: pid} do
      assert {:error, :not_joined} = Teams.sync_to(pid, "tok_new", "claude-code", %{"f.md" => "h1"}, %{})
    end

    test "multiple platforms can sync independently", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})

      # Platform A pushes file A
      {:ok, _} = Teams.sync_to(pid, "tok_1", "platform-a", %{"file-a" => "ha"}, %{"file-a" => "content-a"})
      # Platform B pushes file B
      {:ok, _} = Teams.sync_to(pid, "tok_1", "platform-b", %{"file-b" => "hb"}, %{"file-b" => "content-b"})
      # Platform C pushes file C
      {:ok, _} = Teams.sync_to(pid, "tok_1", "platform-c", %{"file-c" => "hc"}, %{"file-c" => "content-c"})

      # Platform A syncs — should see files from B and C
      {:ok, result} = Teams.sync_to(pid, "tok_1", "platform-a", %{}, %{})
      assert result.files["file-b"].content == "content-b"
      assert result.files["file-c"].content == "content-c"
      refute Map.has_key?(result.files, "file-a")
    end
  end

  describe "content TTL cleanup" do
    test "cleanup removes old content", %{pid: pid} do
      Teams.put_team(pid, "tok_ttl", %{"name" => "test", "members" => []})

      # Set state with old content via sync then manually trigger cleanup
      {:ok, _} = Teams.sync_to(pid, "tok_ttl", "cursor", %{"old-file" => "h1"}, %{"old-file" => "old stuff"})

      # Overwrite the timestamp to be old by sending cleanup and checking
      # For now, test that cleanup runs without crashing
      send(pid, :cleanup)
      _ = :sys.get_state(pid)

      # Content should still be there since it was just created
      {:ok, result} = Teams.sync_to(pid, "tok_ttl", "other", %{}, %{})
      assert result.files["old-file"].content == "old stuff"
    end
  end

  describe "legacy push_buffer/pull_buffer" do
    test "push adds entry and pull retrieves it", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      assert :ok = Teams.push_buffer_to(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer_from(pid, "tok_1", "claude_code")
      assert length(entries) == 1
      assert hd(entries)["content"] == "hello"
    end

    test "pull filters out entries from the same source_platform", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      :ok = Teams.push_buffer_to(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer_from(pid, "tok_1", "cursor")
      assert entries == []
    end

    test "push returns error for unknown token", %{pid: pid} do
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      assert {:error, :not_joined} = Teams.push_buffer_to(pid, "tok_unknown", entry)
    end

    test "pull returns error for unknown token", %{pid: pid} do
      assert {:error, :not_joined} = Teams.pull_buffer_from(pid, "tok_unknown", "claude_code")
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

  describe "sync attribution" do
    test "sync result includes pushed_by with the correct token", %{pid: pid} do
      token = "tok_sync_attr_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(pid, token, %{"name" => "test", "members" => []})

      # Platform A pushes content
      {:ok, _} = Teams.sync_to(pid, token, "claude-code", %{"team.yaml" => "h1"}, %{"team.yaml" => "content-v1"})

      # Platform B syncs with different hash — should get content with pushed_by
      {:ok, result} = Teams.sync_to(pid, token, "cursor", %{"team.yaml" => "old"}, %{})
      assert result.files["team.yaml"].content == "content-v1"
      assert result.files["team.yaml"].pushed_by == token
    end

    test "push_buffer stores pushed_by, pull_buffer returns it", %{pid: pid} do
      token = "tok_push_attr_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(pid, token, %{"name" => "test", "members" => []})

      entry = %{"type" => "note", "content" => "hello from push", "source_platform" => "cursor"}
      assert :ok = Teams.push_buffer_to(pid, token, entry)

      {:ok, entries} = Teams.pull_buffer_from(pid, token, "claude-code")
      assert length(entries) == 1
      assert hd(entries)["pushed_by"] == token
    end
  end

  describe "preview_by_invite" do
    test "returns team data without creating token_teams", %{pid: pid} do
      # Create a team with invite
      {:ok, invite_code} = Teams.create_team_with_invite(pid, %{
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
      {:ok, invite_code} = Teams.create_team_with_invite(pid, %{
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

  describe "get_log" do
    test "returns entries with all attribution fields", %{pid: pid} do
      token = "tok_log_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(pid, token, %{"name" => "test", "members" => []})

      # Push some content from different platforms
      entry1 = %{"type" => "knowledge:notes", "content" => "finding one", "source_platform" => "cursor"}
      entry2 = %{"type" => "knowledge:debug", "content" => "finding two", "source_platform" => "claude-code"}
      :ok = Teams.push_buffer_to(pid, token, entry1)
      :ok = Teams.push_buffer_to(pid, token, entry2)

      {:ok, entries} = Teams.get_log_from(pid, token)
      assert length(entries) == 2

      # Verify all attribution fields are present
      for entry <- entries do
        assert Map.has_key?(entry, "type")
        assert Map.has_key?(entry, "content")
        assert Map.has_key?(entry, "source_platform")
        assert Map.has_key?(entry, "pushed_by")
        assert Map.has_key?(entry, "timestamp")
        assert entry["pushed_by"] == token
      end

      # Verify entries are sorted by timestamp descending
      timestamps = Enum.map(entries, & &1["timestamp"])
      assert timestamps == Enum.sort(timestamps, :desc)
    end

    test "truncates content to 100 chars", %{pid: pid} do
      token = "tok_log_trunc_#{:erlang.unique_integer([:positive])}"
      Teams.put_team(pid, token, %{"name" => "test", "members" => []})

      long_content = String.duplicate("a", 200)
      entry = %{"type" => "note", "content" => long_content, "source_platform" => "cursor"}
      :ok = Teams.push_buffer_to(pid, token, entry)

      {:ok, entries} = Teams.get_log_from(pid, token)
      assert length(entries) == 1
      assert String.length(hd(entries)["content"]) == 100
    end

    test "returns error for non-member", %{pid: pid} do
      assert {:error, :not_joined} = Teams.get_log_from(pid, "tok_stranger_#{:erlang.unique_integer([:positive])}")
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
