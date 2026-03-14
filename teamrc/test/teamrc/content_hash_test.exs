defmodule Teamrc.ContentHashTest do
  use ExUnit.Case, async: true

  alias Teamrc.ContentHash

  # Pre-computed SHA-256 hex values for test vectors
  @empty_array_hash :crypto.hash(:sha256, "[]") |> Base.encode16(case: :lower)
  @empty_string_hash :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)

  describe "compute_members_hash/1" do
    test "empty members list" do
      assert ContentHash.compute_members_hash([]) == @empty_array_hash
    end

    test "single member with string keys" do
      members = [%{"name" => "alice", "role" => "dev"}]
      expected = :crypto.hash(:sha256, ~s([{"name":"alice","role":"dev"}])) |> Base.encode16(case: :lower)
      assert ContentHash.compute_members_hash(members) == expected
    end

    test "single member with atom keys" do
      members = [%{name: "alice", role: "dev"}]
      expected = :crypto.hash(:sha256, ~s([{"name":"alice","role":"dev"}])) |> Base.encode16(case: :lower)
      assert ContentHash.compute_members_hash(members) == expected
    end

    test "members are sorted by name" do
      members = [
        %{"name" => "charlie", "role" => "ops"},
        %{"name" => "alice", "role" => "dev"},
        %{"name" => "bob", "role" => "qa"}
      ]

      # Should produce same hash regardless of input order
      shuffled = [
        %{"name" => "bob", "role" => "qa"},
        %{"name" => "charlie", "role" => "ops"},
        %{"name" => "alice", "role" => "dev"}
      ]

      assert ContentHash.compute_members_hash(members) == ContentHash.compute_members_hash(shuffled)
    end

    test "nil and empty values are omitted" do
      # A member with nil soul and empty skills should produce same hash as one without those keys
      member_with_nils = [%{"name" => "alice", "role" => "dev", "soul" => nil, "skills" => []}]
      member_without = [%{"name" => "alice", "role" => "dev"}]

      assert ContentHash.compute_members_hash(member_with_nils) == ContentHash.compute_members_hash(member_without)
    end

    test "member with soul and skills included" do
      members = [%{"name" => "alice", "role" => "dev", "soul" => "helpful", "skills" => ["coding", "review"]}]
      hash = ContentHash.compute_members_hash(members)

      expected_json = ~s([{"name":"alice","role":"dev","skills":["coding","review"],"soul":"helpful"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "keys are sorted lexicographically" do
      # Verify that keys come out in alphabetical order: name, role, skills, soul
      members = [%{"soul" => "kind", "name" => "alice", "skills" => ["a"], "role" => "dev"}]
      hash = ContentHash.compute_members_hash(members)

      expected_json = ~s([{"name":"alice","role":"dev","skills":["a"],"soul":"kind"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "member with description included in hash" do
      members = [%{"name" => "alice", "role" => "dev", "description" => "Builds APIs"}]
      hash = ContentHash.compute_members_hash(members)

      expected_json = ~s([{"description":"Builds APIs","name":"alice","role":"dev"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "nil description is omitted from hash" do
      member_with_nil = [%{"name" => "alice", "role" => "dev", "description" => nil}]
      member_without = [%{"name" => "alice", "role" => "dev"}]

      assert ContentHash.compute_members_hash(member_with_nil) == ContentHash.compute_members_hash(member_without)
    end

    test "empty string description is omitted from hash" do
      member_with_empty = [%{"name" => "alice", "role" => "dev", "description" => ""}]
      member_without = [%{"name" => "alice", "role" => "dev"}]

      assert ContentHash.compute_members_hash(member_with_empty) == ContentHash.compute_members_hash(member_without)
    end

    test "description key is sorted alphabetically (before name)" do
      members = [%{"name" => "alice", "role" => "dev", "description" => "desc", "soul" => "kind", "skills" => ["a"]}]
      hash = ContentHash.compute_members_hash(members)

      # Keys in alphabetical order: description, name, role, skills, soul
      expected_json = ~s([{"description":"desc","name":"alice","role":"dev","skills":["a"],"soul":"kind"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "skills within a member are sorted" do
      members = [%{"name" => "alice", "role" => "dev", "skills" => ["review", "coding"]}]
      hash = ContentHash.compute_members_hash(members)

      # skills sorted: ["coding", "review"]
      expected_json = ~s([{"name":"alice","role":"dev","skills":["coding","review"]}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end
  end

  describe "compute_skills_hash/1" do
    test "empty skills list" do
      assert ContentHash.compute_skills_hash([]) == @empty_array_hash
    end

    test "single skill" do
      skills = [%{"id" => "linting", "body" => "Use eslint"}]
      hash = ContentHash.compute_skills_hash(skills)

      expected_json = ~s([{"body":"Use eslint","id":"linting"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "skills are sorted by id" do
      skills = [
        %{"id" => "testing", "body" => "Write tests"},
        %{"id" => "linting", "body" => "Use eslint"}
      ]

      reversed = Enum.reverse(skills)
      assert ContentHash.compute_skills_hash(skills) == ContentHash.compute_skills_hash(reversed)
    end

    test "globs are sorted within each skill" do
      skills = [%{"id" => "lint", "globs" => ["*.ts", "*.js"]}]
      skills_sorted = [%{"id" => "lint", "globs" => ["*.js", "*.ts"]}]

      assert ContentHash.compute_skills_hash(skills) == ContentHash.compute_skills_hash(skills_sorted)
    end

    test "nil and empty values are omitted from skills" do
      skill_with_nils = [%{"id" => "lint", "body" => "do it", "title" => nil, "globs" => []}]
      skill_without = [%{"id" => "lint", "body" => "do it"}]

      assert ContentHash.compute_skills_hash(skill_with_nils) == ContentHash.compute_skills_hash(skill_without)
    end

    test "boolean values are encoded correctly" do
      skills = [%{"id" => "lint", "alwaysApply" => true}]
      hash = ContentHash.compute_skills_hash(skills)

      expected_json = ~s([{"alwaysApply":true,"id":"lint"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "alwaysApply false is included, not omitted" do
      skills_with_false = [%{"id" => "lint", "alwaysApply" => false, "body" => "do it"}]
      skills_without = [%{"id" => "lint", "body" => "do it"}]

      hash_with = ContentHash.compute_skills_hash(skills_with_false)
      hash_without = ContentHash.compute_skills_hash(skills_without)

      # false is a meaningful value, so hash should differ
      assert hash_with != hash_without

      expected_json = ~s([{"alwaysApply":false,"body":"do it","id":"lint"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash_with == expected
    end

    test "atom-keyed boolean fields are handled correctly" do
      skills = [%{id: "lint", alwaysApply: false, body: "do it"}]
      hash = ContentHash.compute_skills_hash(skills)

      expected_json = ~s([{"alwaysApply":false,"body":"do it","id":"lint"}])
      expected = :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
      assert hash == expected
    end
  end

  describe "compute_knowledge_hash/1" do
    test "nil knowledge" do
      assert ContentHash.compute_knowledge_hash(nil) == @empty_string_hash
    end

    test "empty string knowledge" do
      assert ContentHash.compute_knowledge_hash("") == @empty_string_hash
    end

    test "knowledge with trailing newline" do
      hash = ContentHash.compute_knowledge_hash("# Knowledge\n")
      expected = :crypto.hash(:sha256, "# Knowledge\n") |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "knowledge without trailing newline gets one added" do
      hash = ContentHash.compute_knowledge_hash("# Knowledge")
      expected = :crypto.hash(:sha256, "# Knowledge\n") |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "knowledge with multiple trailing newlines is normalized to one" do
      hash = ContentHash.compute_knowledge_hash("# Knowledge\n\n\n")
      expected = :crypto.hash(:sha256, "# Knowledge\n") |> Base.encode16(case: :lower)
      assert hash == expected
    end
  end

  describe "compute_full_hash/3" do
    test "combines three component hashes" do
      mh = "aaa"
      sh = "bbb"
      kh = "ccc"
      expected = :crypto.hash(:sha256, "aaa:bbb:ccc") |> Base.encode16(case: :lower)
      assert ContentHash.compute_full_hash(mh, sh, kh) == expected
    end

    test "empty team produces deterministic hash" do
      mh = ContentHash.compute_members_hash([])
      sh = ContentHash.compute_skills_hash([])
      kh = ContentHash.compute_knowledge_hash(nil)
      full = ContentHash.compute_full_hash(mh, sh, kh)

      # Verify it is a 64-char lowercase hex string
      assert String.length(full) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, full)
    end
  end

  describe "compute_team_hashes/1" do
    test "works with a map with atom keys" do
      team = %{
        members: [%{name: "alice", role: "dev"}],
        skills: [],
        knowledge: nil
      }

      hashes = ContentHash.compute_team_hashes(team)
      assert is_binary(hashes.hash)
      assert is_binary(hashes.members_hash)
      assert is_binary(hashes.skills_hash)
      assert is_binary(hashes.knowledge_hash)
      assert String.length(hashes.hash) == 64
    end

    test "works with a map with string keys" do
      team = %{
        "members" => [%{"name" => "alice", "role" => "dev"}],
        "skills" => [],
        "knowledge" => nil
      }

      hashes = ContentHash.compute_team_hashes(team)
      assert is_binary(hashes.hash)
      assert String.length(hashes.hash) == 64
    end

    test "full hash is derived from component hashes" do
      team = %{
        members: [%{name: "alice", role: "dev"}],
        skills: [%{"id" => "lint", "body" => "do it"}],
        knowledge: "notes\n"
      }

      hashes = ContentHash.compute_team_hashes(team)
      expected_full = ContentHash.compute_full_hash(hashes.members_hash, hashes.skills_hash, hashes.knowledge_hash)
      assert hashes.hash == expected_full
    end
  end

  describe "merge_knowledge/2" do
    test "nil existing returns incoming" do
      assert ContentHash.merge_knowledge(nil, "new stuff") == "new stuff"
    end

    test "nil incoming returns existing" do
      assert ContentHash.merge_knowledge("existing", nil) == "existing"
    end

    test "empty existing returns incoming" do
      assert ContentHash.merge_knowledge("", "new stuff") == "new stuff"
    end

    test "empty incoming returns existing" do
      assert ContentHash.merge_knowledge("existing", "") == "existing"
    end

    test "appends new lines from incoming" do
      existing = "line1\nline2\n"
      incoming = "line2\nline3\n"
      result = ContentHash.merge_knowledge(existing, incoming)
      assert result == "line1\nline2\nline3\n"
    end

    test "no duplicates when all lines already present" do
      existing = "line1\nline2\nline3\n"
      incoming = "line1\nline2\n"
      result = ContentHash.merge_knowledge(existing, incoming)
      assert result == existing
    end

    test "handles whitespace-only differences in dedup" do
      existing = "  line1  \nline2\n"
      incoming = "line1\nline3\n"
      # "line1" (trimmed) matches "  line1  " (trimmed), so only line3 is new
      result = ContentHash.merge_knowledge(existing, incoming)
      assert String.contains?(result, "line3")
      refute result |> String.split("\n") |> Enum.count(&(&1 =~ ~r/line1/)) > 1
    end

    test "result ends with newline when lines are appended" do
      existing = "line1"
      incoming = "line2"
      result = ContentHash.merge_knowledge(existing, incoming)
      assert String.ends_with?(result, "\n")
    end
  end

  describe "known test vectors" do
    test "empty team vector" do
      members_hash = ContentHash.compute_members_hash([])
      skills_hash = ContentHash.compute_skills_hash([])
      knowledge_hash = ContentHash.compute_knowledge_hash(nil)

      assert members_hash == @empty_array_hash
      assert skills_hash == @empty_array_hash
      assert knowledge_hash == @empty_string_hash
    end

    test "simple team vector" do
      members_hash = ContentHash.compute_members_hash([%{"name" => "alice", "role" => "dev"}])
      skills_hash = ContentHash.compute_skills_hash([])
      knowledge_hash = ContentHash.compute_knowledge_hash("# Knowledge\n")

      assert members_hash ==
               :crypto.hash(:sha256, ~s([{"name":"alice","role":"dev"}])) |> Base.encode16(case: :lower)

      assert skills_hash == @empty_array_hash

      assert knowledge_hash ==
               :crypto.hash(:sha256, "# Knowledge\n") |> Base.encode16(case: :lower)
    end

    test "hash is always 64-char lowercase hex" do
      for input <- [[], [%{"name" => "a", "role" => "b"}]] do
        hash = ContentHash.compute_members_hash(input)
        assert String.length(hash) == 64
        assert Regex.match?(~r/^[0-9a-f]{64}$/, hash)
      end
    end
  end
end
