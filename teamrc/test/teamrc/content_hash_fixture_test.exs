defmodule Teamrc.ContentHashFixtureTest do
  @moduledoc """
  Cross-language integration tests for canonical JSON hashing.

  These tests read shared fixture vectors from test-fixtures/canonical-hash-vectors.json
  and verify that the Elixir implementation produces identical results to TypeScript.
  The same fixture file is tested by the TypeScript implementation in
  cli/src/__tests__/sync-hash-fixtures.test.ts.

  If either implementation changes its output, these tests catch the divergence.
  """
  use ExUnit.Case, async: true

  alias Teamrc.ContentHash

  @fixture_path Path.join([__DIR__, "..", "..", "..", "test-fixtures", "canonical-hash-vectors.json"])

  setup_all do
    fixtures =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()

    %{fixtures: fixtures}
  end

  describe "cross-language fixture: member vectors" do
    test "all member vectors match expected hashes", %{fixtures: fixtures} do
      for vector <- fixtures["memberVectors"] do
        members = normalize_members(vector["members"])
        hash = ContentHash.compute_members_hash(members)

        assert hash == vector["expectedHash"],
               """
               Members hash mismatch for "#{vector["description"]}".
               Expected: #{vector["expectedHash"]}
               Got:      #{hash}
               Expected canonical JSON: #{vector["expectedCanonicalJson"]}
               """
      end
    end
  end

  describe "cross-language fixture: skill vectors" do
    test "all skill vectors match expected hashes", %{fixtures: fixtures} do
      for vector <- fixtures["skillVectors"] do
        skills = normalize_skills(vector["skills"])
        hash = ContentHash.compute_skills_hash(skills)

        assert hash == vector["expectedHash"],
               """
               Skills hash mismatch for "#{vector["description"]}".
               Expected: #{vector["expectedHash"]}
               Got:      #{hash}
               Expected canonical JSON: #{vector["expectedCanonicalJson"]}
               """
      end
    end
  end

  describe "cross-language fixture: knowledge vectors" do
    test "all knowledge vectors match expected hashes", %{fixtures: fixtures} do
      for vector <- fixtures["knowledgeVectors"] do
        knowledge = vector["knowledge"]
        hash = ContentHash.compute_knowledge_hash(knowledge)

        assert hash == vector["expectedHash"],
               """
               Knowledge hash mismatch for "#{vector["description"]}".
               Expected: #{vector["expectedHash"]}
               Got:      #{hash}
               Input:    #{inspect(knowledge)}
               """
      end
    end
  end

  describe "cross-language fixture: full hash vectors" do
    test "all full hash vectors match expected hashes", %{fixtures: fixtures} do
      for vector <- fixtures["fullHashVectors"] do
        hash =
          ContentHash.compute_full_hash(
            vector["membersHash"],
            vector["skillsHash"],
            vector["knowledgeHash"]
          )

        assert hash == vector["expectedHash"],
               """
               Full hash mismatch for "#{vector["description"]}".
               Expected: #{vector["expectedHash"]}
               Got:      #{hash}
               Input:    #{vector["expectedInput"]}
               """
      end
    end
  end

  # Normalize fixture member data into string-keyed maps matching what the Elixir
  # implementation expects. JSON decode gives us string keys, which is correct.
  # We just need to ensure the structure is right.
  defp normalize_members(members) when is_list(members) do
    Enum.map(members, fn member ->
      member
      |> Map.take(["name", "role", "soul", "skills"])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  # Normalize fixture skill data into string-keyed maps.
  defp normalize_skills(skills) when is_list(skills) do
    Enum.map(skills, fn skill ->
      skill
      |> Map.take(["id", "title", "description", "body", "alwaysApply", "globs", "userInvocable"])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end
end
