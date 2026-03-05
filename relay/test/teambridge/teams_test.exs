defmodule Teambridge.TeamsTest do
  use ExUnit.Case, async: true

  alias Teambridge.Teams

  setup do
    name = :"teams_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Teams.start_link(name: name)
    %{pid: pid}
  end

  describe "put_team/get_team" do
    test "stores and retrieves a team", %{pid: pid} do
      team = %{"name" => "My Team", "agents" => ["agent1"]}
      assert :ok = Teams.put_team(pid, "tok_123", team)
      assert {:ok, ^team} = Teams.get_team(pid, "tok_123")
    end

    test "returns :error for unknown token", %{pid: pid} do
      assert :error = Teams.get_team(pid, "tok_unknown")
    end
  end

  describe "push_buffer/pull_buffer" do
    test "push adds entry and pull retrieves it", %{pid: pid} do
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      assert :ok = Teams.push_buffer(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_1", "claude_code")
      assert length(entries) == 1
      assert hd(entries)["content"] == "hello"
    end

    test "pull filters out entries from the same source_platform", %{pid: pid} do
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      :ok = Teams.push_buffer(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_1", "cursor")
      assert entries == []
    end

    test "pull marks entries as delivered and does not return them again", %{pid: pid} do
      entry = %{"type" => "message", "content" => "hello", "source_platform" => "cursor"}
      :ok = Teams.push_buffer(pid, "tok_1", entry)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_1", "claude_code")
      assert length(entries) == 1

      {:ok, entries2} = Teams.pull_buffer(pid, "tok_1", "claude_code")
      assert entries2 == []
    end

    test "pull returns empty list for unknown token", %{pid: pid} do
      {:ok, entries} = Teams.pull_buffer(pid, "tok_unknown", "claude_code")
      assert entries == []
    end
  end

  describe "put_hashes/get_changes" do
    test "get_changes returns hashes from other platforms", %{pid: pid} do
      hashes_cursor = %{"file1.ex" => "abc123", "file2.ex" => "def456"}
      hashes_claude = %{"file1.ex" => "abc123", "file3.ex" => "ghi789"}

      :ok = Teams.put_hashes(pid, "tok_1", "cursor", hashes_cursor)
      :ok = Teams.put_hashes(pid, "tok_1", "claude_code", hashes_claude)

      {:ok, changes} = Teams.get_changes(pid, "tok_1", "cursor")
      # Should return changes from claude_code (other platforms), not cursor's own
      assert changes == %{"claude_code" => hashes_claude}
    end

    test "get_changes returns empty map when no other platforms", %{pid: pid} do
      hashes = %{"file1.ex" => "abc123"}
      :ok = Teams.put_hashes(pid, "tok_1", "cursor", hashes)

      {:ok, changes} = Teams.get_changes(pid, "tok_1", "cursor")
      assert changes == %{}
    end

    test "get_changes returns empty map for unknown token", %{pid: pid} do
      {:ok, changes} = Teams.get_changes(pid, "tok_unknown", "cursor")
      assert changes == %{}
    end
  end

  describe "buffer TTL cleanup" do
    test "cleanup removes entries with old timestamps", %{pid: pid} do
      old_entry = %{
        "type" => "message",
        "content" => "old",
        "source_platform" => "cursor",
        "timestamp" => "2020-01-01T00:00:00Z"
      }

      :ok = Teams.push_buffer(pid, "tok_ttl", old_entry)

      # Trigger cleanup
      send(pid, :cleanup)
      Process.sleep(50)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_ttl", "claude_code")
      assert entries == []
    end

    test "cleanup keeps recent entries", %{pid: pid} do
      recent_entry = %{
        "type" => "message",
        "content" => "recent",
        "source_platform" => "cursor"
      }

      :ok = Teams.push_buffer(pid, "tok_ttl2", recent_entry)

      send(pid, :cleanup)
      Process.sleep(50)

      {:ok, entries} = Teams.pull_buffer(pid, "tok_ttl2", "claude_code")
      assert length(entries) == 1
    end
  end

  describe "multi-platform buffer" do
    test "multiple platforms can push and pull independently", %{pid: pid} do
      Teams.put_team(pid, "tb_ak_multi", %{"name" => "test", "members" => []})

      # Push from 3 different platforms
      Teams.push_buffer(pid, "tb_ak_multi", %{"content" => "from-a", "source_platform" => "a"})
      Teams.push_buffer(pid, "tb_ak_multi", %{"content" => "from-b", "source_platform" => "b"})
      Teams.push_buffer(pid, "tb_ak_multi", %{"content" => "from-c", "source_platform" => "c"})

      # Platform A should see entries from B and C only
      {:ok, a_entries} = Teams.pull_buffer(pid, "tb_ak_multi", "a")
      assert length(a_entries) == 2
      contents = Enum.map(a_entries, & &1["content"])
      assert "from-b" in contents
      assert "from-c" in contents
      refute "from-a" in contents
    end
  end

  describe "hash changes across platforms" do
    test "get_changes returns hashes from other platforms only", %{pid: pid} do
      Teams.put_team(pid, "tb_ak_new", %{"name" => "test", "members" => []})
      Teams.put_hashes(pid, "tb_ak_new", "openclaw", %{"new-file.md" => "hash1"})

      # claude-code has no files
      Teams.put_hashes(pid, "tb_ak_new", "claude-code", %{})
      {:ok, changes} = Teams.get_changes(pid, "tb_ak_new", "claude-code")
      # changes should contain the openclaw hashes but not claude-code's own
      assert changes == %{"openclaw" => %{"new-file.md" => "hash1"}}
      refute Map.has_key?(changes, "claude-code")
    end
  end

  describe "put_team overwrite" do
    test "put_team overwrites existing team", %{pid: pid} do
      Teams.put_team(pid, "tb_ak_overwrite", %{"name" => "v1", "members" => []})
      Teams.put_team(pid, "tb_ak_overwrite", %{"name" => "v2", "members" => [%{"name" => "new"}]})
      {:ok, team} = Teams.get_team(pid, "tb_ak_overwrite")
      assert team["name"] == "v2"
      assert length(team["members"]) == 1
    end
  end
end
