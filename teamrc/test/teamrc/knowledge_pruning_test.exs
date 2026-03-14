defmodule Teamrc.KnowledgePruningTest do
  use ExUnit.Case, async: true

  alias Teamrc.ContentHash

  describe "parse_knowledge/1" do
    test "nil returns empty preamble and no sections" do
      result = ContentHash.parse_knowledge(nil)
      assert result == %{preamble: "", sections: []}
    end

    test "empty string returns empty preamble and no sections" do
      result = ContentHash.parse_knowledge("")
      assert result == %{preamble: "", sections: []}
    end

    test "preamble-only content with no ## headings" do
      content = "# Team Knowledge\n\nShared findings.\n\nTest commands here.\n"
      result = ContentHash.parse_knowledge(content)

      assert result.preamble == "# Team Knowledge\n\nShared findings.\n\nTest commands here.\n"
      assert result.sections == []
    end

    test "content with a single section" do
      content = "# Title\n\n## Database indexing\nFound composite index needed.\n"
      result = ContentHash.parse_knowledge(content)

      assert result.preamble == "# Title\n"
      assert length(result.sections) == 1

      [section] = result.sections
      assert section.heading == "Database indexing"
      assert section.body == "## Database indexing\nFound composite index needed.\n"
    end

    test "content with multiple sections ordered correctly" do
      content = """
      # Knowledge

      ## First topic
      Details about first.

      ## Second topic
      Details about second.

      ## Third topic
      Details about third.
      """

      result = ContentHash.parse_knowledge(content)

      assert result.preamble == "# Knowledge\n"
      assert length(result.sections) == 3

      [s1, s2, s3] = result.sections
      assert s1.heading == "First topic"
      assert s2.heading == "Second topic"
      assert s3.heading == "Third topic"

      # Each section body starts with its ## heading
      assert String.starts_with?(s1.body, "## First topic")
      assert String.starts_with?(s2.body, "## Second topic")
      assert String.starts_with?(s3.body, "## Third topic")
    end

    test "section body includes all lines until next section" do
      content = "## Auth\nLine 1\nLine 2\nLine 3\n## Next\nOther\n"
      result = ContentHash.parse_knowledge(content)

      assert result.preamble == ""
      assert length(result.sections) == 2

      [auth, next_section] = result.sections
      assert auth.heading == "Auth"
      assert auth.body == "## Auth\nLine 1\nLine 2\nLine 3"
      assert next_section.heading == "Next"
      assert next_section.body == "## Next\nOther\n"
    end

    test "### headings are not treated as section boundaries" do
      content = "## Main section\nSome text\n### Subsection\nMore text\n"
      result = ContentHash.parse_knowledge(content)

      assert length(result.sections) == 1
      [section] = result.sections
      assert section.heading == "Main section"
      assert String.contains?(section.body, "### Subsection")
      assert String.contains?(section.body, "More text")
    end

    test "preamble over 10KB is truncated at line boundary" do
      # Generate preamble lines that exceed 10KB
      # Each line is ~100 bytes, so 110 lines = ~11KB
      lines =
        for i <- 1..110 do
          "Line #{i}: " <> String.duplicate("x", 90)
        end

      content = Enum.join(lines, "\n") <> "\n## After preamble\nSection content\n"
      result = ContentHash.parse_knowledge(content)

      # Preamble should be truncated to fit within 10KB
      assert byte_size(result.preamble) <= 10_240

      # But it should still contain some lines
      assert String.contains?(result.preamble, "Line 1:")

      # The section should still be parsed
      assert length(result.sections) == 1
      assert hd(result.sections).heading == "After preamble"
    end

    test "content starting with a section (no preamble)" do
      content = "## First\nBody here\n"
      result = ContentHash.parse_knowledge(content)

      assert result.preamble == ""
      assert length(result.sections) == 1
      assert hd(result.sections).heading == "First"
    end
  end

  describe "prune_knowledge/2" do
    test "nil returns empty string" do
      assert ContentHash.prune_knowledge(nil) == ""
    end

    test "empty string returns empty string" do
      assert ContentHash.prune_knowledge("") == ""
    end

    test "content under limit is returned unchanged" do
      content = "# Knowledge\n\n## Topic\nSome info.\n"
      assert ContentHash.prune_knowledge(content, 100_000) == content
    end

    test "content exactly at limit is returned unchanged" do
      content = String.duplicate("x", 1000)
      assert ContentHash.prune_knowledge(content, 1000) == content
    end

    test "content over limit drops oldest sections first" do
      preamble = "# Knowledge\n"

      sections =
        for i <- 1..10 do
          "## Section #{i}\n" <> String.duplicate("a", 100) <> "\n"
        end

      content = preamble <> Enum.join(sections, "\n")
      # Set a small max to force pruning
      max_bytes = div(byte_size(content), 2)
      result = ContentHash.prune_knowledge(content, max_bytes)

      # Preamble should be preserved
      assert String.starts_with?(result, "# Knowledge\n")

      # Result should fit within 80% of max_bytes
      assert byte_size(result) <= trunc(max_bytes * 0.8)

      # Newest sections should be preserved (Section 10, 9, etc.)
      assert String.contains?(result, "## Section 10")

      # Oldest sections should be dropped (Section 1, 2, etc.)
      refute String.contains?(result, "## Section 1\n")
    end

    test "preamble is always preserved even when over limit" do
      preamble = "# Important Knowledge\nKey info line 1\nKey info line 2\n"
      section = "## Old topic\n" <> String.duplicate("x", 200) <> "\n"
      content = preamble <> section

      # Set max below total but above preamble size
      max_bytes = byte_size(preamble) + 10
      result = ContentHash.prune_knowledge(content, max_bytes)

      # Preamble should be intact
      assert String.starts_with?(result, "# Important Knowledge")
      assert String.contains?(result, "Key info line 1")
    end

    test "pruned content is within 80% of max_bytes" do
      sections =
        for i <- 1..20 do
          "## Section #{i}\n" <> String.duplicate("data ", 200) <> "\n"
        end

      content = "# Preamble\n" <> Enum.join(sections, "\n")
      max_bytes = 5000
      result = ContentHash.prune_knowledge(content, max_bytes)

      assert byte_size(result) <= trunc(max_bytes * 0.8)
    end

    test "all sections dropped if needed, only preamble remains" do
      preamble = "# Knowledge\nEssential info\n"

      sections =
        for i <- 1..5 do
          "## Section #{i}\n" <> String.duplicate("y", 500) <> "\n"
        end

      content = preamble <> Enum.join(sections, "\n")
      # Max is just above preamble size, so all sections must be dropped
      max_bytes = byte_size(preamble) + 50
      result = ContentHash.prune_knowledge(content, max_bytes)

      assert result == preamble
    end

    test "preserves section boundaries (no partial section removal)" do
      content = "# KB\n## A\nAAA\n## B\nBBB\n## C\nCCC\n"
      max_bytes = byte_size(content) - 5
      result = ContentHash.prune_knowledge(content, max_bytes)

      # Each remaining section should be complete
      parsed = ContentHash.parse_knowledge(result)

      for section <- parsed.sections do
        assert String.starts_with?(section.body, "## ")
      end
    end

    test "default max_bytes is 100_000" do
      # Content under 100KB should pass through unchanged
      content = "# Knowledge\n## Topic\nInfo\n"
      assert ContentHash.prune_knowledge(content) == content
    end
  end
end
