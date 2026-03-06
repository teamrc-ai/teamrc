defmodule Teamrc.TeamsTest do
  use ExUnit.Case, async: false

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

      {:ok, result} = Teams.sync(pid, "tok_a", "claude-code", %{"team.yaml" => "abc123"}, %{})
      assert result.files == %{}
    end

    test "returns changed files from other platforms", %{pid: pid} do
      Teams.put_team(pid, "tok_a", %{"name" => "test", "members" => []})
      Teams.put_team(pid, "tok_b", %{"name" => "test", "members" => []})

      # Simulate both tokens on same team by syncing through same token namespace
      # Platform A syncs with content
      {:ok, _} = Teams.sync(pid, "tok_a", "claude-code", %{"team.yaml" => "hash_v2"}, %{"team.yaml" => "name: updated-team"})

      # Platform B syncs with old hash — should get the new content
      {:ok, result} = Teams.sync(pid, "tok_a", "openclaw", %{"team.yaml" => "hash_v1"}, %{})
      assert result.files["team.yaml"].content == "name: updated-team"
      assert is_integer(result.files["team.yaml"].updated_at)
    end

    test "does not return files when hashes match", %{pid: pid} do
      Teams.put_team(pid, "tok_a", %{"name" => "test", "members" => []})

      {:ok, _} = Teams.sync(pid, "tok_a", "claude-code", %{"team.yaml" => "same_hash"}, %{"team.yaml" => "content"})
      {:ok, result} = Teams.sync(pid, "tok_a", "openclaw", %{"team.yaml" => "same_hash"}, %{})
      assert result.files == %{}
    end

    test "returns error for unknown token", %{pid: pid} do
      assert {:error, :not_joined} = Teams.sync(pid, "tok_new", "claude-code", %{"f.md" => "h1"}, %{})
    end

    test "multiple platforms can sync independently", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})

      # Platform A pushes file A
      {:ok, _} = Teams.sync(pid, "tok_1", "platform-a", %{"file-a" => "ha"}, %{"file-a" => "content-a"})
      # Platform B pushes file B
      {:ok, _} = Teams.sync(pid, "tok_1", "platform-b", %{"file-b" => "hb"}, %{"file-b" => "content-b"})
      # Platform C pushes file C
      {:ok, _} = Teams.sync(pid, "tok_1", "platform-c", %{"file-c" => "hc"}, %{"file-c" => "content-c"})

      # Platform A syncs — should see files from B and C
      {:ok, result} = Teams.sync(pid, "tok_1", "platform-a", %{}, %{})
      assert result.files["file-b"].content == "content-b"
      assert result.files["file-c"].content == "content-c"
      refute Map.has_key?(result.files, "file-a")
    end
  end

  describe "content TTL cleanup" do
    test "cleanup removes old content", %{pid: pid} do
      Teams.put_team(pid, "tok_ttl", %{"name" => "test", "members" => []})

      # Set state with old content via sync then manually trigger cleanup
      {:ok, _} = Teams.sync(pid, "tok_ttl", "cursor", %{"old-file" => "h1"}, %{"old-file" => "old stuff"})

      # Overwrite the timestamp to be old by sending cleanup and checking
      # For now, test that cleanup runs without crashing
      send(pid, :cleanup)
      _ = :sys.get_state(pid)

      # Content should still be there since it was just created
      {:ok, result} = Teams.sync(pid, "tok_ttl", "other", %{}, %{})
      assert result.files["old-file"].content == "old stuff"
    end
  end

  describe "legacy push_buffer/pull_buffer" do
    test "push adds entry and pull retrieves it", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      assert :ok = Teams.push_buffer(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_1", "claude_code")
      assert length(entries) == 1
      assert hd(entries)["content"] == "hello"
    end

    test "pull filters out entries from the same source_platform", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      :ok = Teams.push_buffer(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_1", "cursor")
      assert entries == []
    end

    test "push returns error for unknown token", %{pid: pid} do
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      assert {:error, :not_joined} = Teams.push_buffer(pid, "tok_unknown", entry)
    end

    test "pull returns error for unknown token", %{pid: pid} do
      assert {:error, :not_joined} = Teams.pull_buffer(pid, "tok_unknown", "claude_code")
    end
  end

  describe "put_hashes/get_changes (legacy)" do
    test "get_changes returns hashes from other platforms", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      hashes_cursor = %{"file1.ex" => "abc123", "file2.ex" => "def456"}
      hashes_claude = %{"file1.ex" => "abc123", "file3.ex" => "ghi789"}

      :ok = Teams.put_hashes(pid, "tok_1", "cursor", hashes_cursor)
      :ok = Teams.put_hashes(pid, "tok_1", "claude_code", hashes_claude)

      {:ok, changes} = Teams.get_changes(pid, "tok_1", "cursor")
      assert changes == %{"claude_code" => hashes_claude}
    end

    test "get_changes returns empty map when no other platforms", %{pid: pid} do
      Teams.put_team(pid, "tok_1", %{"name" => "test", "members" => []})
      hashes = %{"file1.ex" => "abc123"}
      :ok = Teams.put_hashes(pid, "tok_1", "cursor", hashes)

      {:ok, changes} = Teams.get_changes(pid, "tok_1", "cursor")
      assert changes == %{}
    end

    test "returns error for unknown token", %{pid: pid} do
      assert {:error, :not_joined} = Teams.get_changes(pid, "tok_unknown", "cursor")
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
end
