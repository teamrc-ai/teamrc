defmodule Teamrc.ContentHash do
  @moduledoc """
  Content-addressable hashing for team data. Produces deterministic SHA-256
  hashes that match the TypeScript CLI implementation exactly.

  Hash computation rules:
  - SHA-256 of canonical JSON, output as lowercase hex
  - Canonical JSON: compact (no spaces), keys sorted lexicographically at every level
  - Members array: sorted by `name`; per-member keys sorted; nil/empty values omitted
  - Skills array: sorted by `id`; per-skill keys sorted; nil/empty values omitted; `globs` sorted
  - Knowledge hash: SHA-256 of raw string with trailing newline normalized
  - Full hash: SHA-256 of "members_hash:skills_hash:knowledge_hash"
  """

  @doc "Compute SHA-256 hash of the members list in canonical form."
  @spec compute_members_hash(list(map())) :: String.t()
  def compute_members_hash(members) when is_list(members) do
    members
    |> Enum.sort_by(&member_sort_key/1)
    |> Enum.map(&canonicalize_member/1)
    |> canonical_json_array()
    |> sha256_hex()
  end

  @doc "Compute SHA-256 hash of the skills list in canonical form."
  @spec compute_skills_hash(list(map())) :: String.t()
  def compute_skills_hash(skills) when is_list(skills) do
    skills
    |> Enum.sort_by(&skill_sort_key/1)
    |> Enum.map(&canonicalize_skill/1)
    |> canonical_json_array()
    |> sha256_hex()
  end

  @doc "Compute SHA-256 hash of knowledge content."
  @spec compute_knowledge_hash(String.t() | nil) :: String.t()
  def compute_knowledge_hash(nil), do: sha256_hex("")
  def compute_knowledge_hash(""), do: sha256_hex("")

  def compute_knowledge_hash(knowledge) when is_binary(knowledge) do
    # Normalize trailing newline: exactly one \n at end
    normalized = String.trim_trailing(knowledge) <> "\n"
    sha256_hex(normalized)
  end

  @doc "Compute the full team hash from component hashes."
  @spec compute_full_hash(String.t(), String.t(), String.t()) :: String.t()
  def compute_full_hash(members_hash, skills_hash, knowledge_hash) do
    sha256_hex("#{members_hash}:#{skills_hash}:#{knowledge_hash}")
  end

  @doc "Compute all hashes for a team with preloaded members."
  @spec compute_team_hashes(map()) :: %{
          members_hash: String.t(),
          skills_hash: String.t(),
          knowledge_hash: String.t(),
          hash: String.t()
        }
  def compute_team_hashes(team) do
    members = extract_members(team)
    skills = extract_skills(team)
    knowledge = extract_knowledge(team)

    members_hash = compute_members_hash(members)
    skills_hash = compute_skills_hash(skills)
    knowledge_hash = compute_knowledge_hash(knowledge)
    full_hash = compute_full_hash(members_hash, skills_hash, knowledge_hash)

    %{
      members_hash: members_hash,
      skills_hash: skills_hash,
      knowledge_hash: knowledge_hash,
      hash: full_hash
    }
  end

  @doc """
  Merge knowledge strings using append-only dedup by line content.
  Matches the TypeScript `mergeKnowledge` implementation.
  """
  @spec merge_knowledge(String.t() | nil, String.t() | nil) :: String.t() | nil
  def merge_knowledge(nil, incoming), do: incoming
  def merge_knowledge(existing, nil), do: existing
  def merge_knowledge("", incoming), do: incoming
  def merge_knowledge(existing, ""), do: existing

  def merge_knowledge(existing, incoming) when is_binary(existing) and is_binary(incoming) do
    existing_lines =
      existing
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
      |> MapSet.new()

    new_lines =
      incoming
      |> String.split("\n")
      |> Enum.filter(fn line ->
        trimmed = String.trim(line)
        trimmed != "" and not MapSet.member?(existing_lines, trimmed)
      end)

    if new_lines == [] do
      existing
    else
      String.trim_trailing(existing) <> "\n" <> Enum.join(new_lines, "\n") <> "\n"
    end
  end

  # --- Knowledge parsing and pruning ---

  @max_preamble_bytes 10_240
  @default_max_bytes 100_000

  @typedoc "A parsed knowledge section with heading text and full body (including the ## line)."
  @type knowledge_section :: %{heading: String.t(), body: String.t()}

  @typedoc "Parsed knowledge split into preamble and ordered sections."
  @type parsed_knowledge :: %{preamble: String.t(), sections: [knowledge_section()]}

  @doc """
  Parse a knowledge markdown string into preamble + sections.

  - **Preamble**: Everything before the first `## ` heading, up to 10KB.
    If preamble content exceeds 10KB, it is truncated at a line boundary.
  - **Sections**: Each `## <heading>` line plus all subsequent lines until the
    next `## ` heading or EOF. Ordered as they appear (oldest first = top of file).
  - `nil` or `""` input returns `%{preamble: "", sections: []}`.
  """
  @spec parse_knowledge(String.t() | nil) :: parsed_knowledge()
  def parse_knowledge(nil), do: %{preamble: "", sections: []}
  def parse_knowledge(""), do: %{preamble: "", sections: []}

  def parse_knowledge(content) when is_binary(content) do
    lines = String.split(content, "\n", trim: false)
    {preamble_lines, section_groups} = split_at_sections(lines)

    preamble_raw = Enum.join(preamble_lines, "\n")

    # When sections follow the preamble, the \n before the first ## heading
    # was consumed by String.split. Restore it so the preamble faithfully
    # represents "everything before the first ## heading."
    preamble_raw =
      if section_groups != [] and preamble_raw != "" and
           not String.ends_with?(preamble_raw, "\n") do
        preamble_raw <> "\n"
      else
        preamble_raw
      end

    preamble = truncate_preamble_string(preamble_raw)

    sections =
      Enum.map(section_groups, fn {heading, body_lines} ->
        %{heading: heading, body: Enum.join(body_lines, "\n")}
      end)

    %{preamble: preamble, sections: sections}
  end

  @doc """
  FIFO prune knowledge to fit within a byte limit.

  - Parses content into preamble + sections
  - Preamble is always preserved (up to 10KB, never dropped)
  - If total size <= max_bytes, returns content unchanged
  - Drops sections oldest-first (from front of list) until total size <= 80% of max_bytes
  - Reassembles preamble + remaining sections
  """
  @spec prune_knowledge(String.t() | nil, non_neg_integer()) :: String.t()
  def prune_knowledge(content, max_bytes \\ @default_max_bytes)
  def prune_knowledge(nil, _max_bytes), do: ""
  def prune_knowledge("", _max_bytes), do: ""

  def prune_knowledge(content, max_bytes) when is_binary(content) do
    if byte_size(content) <= max_bytes do
      content
    else
      target = trunc(max_bytes * 0.8)
      %{preamble: preamble, sections: sections} = parse_knowledge(content)

      remaining = drop_oldest_until_fits(preamble, sections, target)
      reassemble(preamble, remaining)
    end
  end

  # Split lines into preamble lines and section groups.
  # Returns {preamble_lines, [{heading, all_lines_including_heading}]}
  defp split_at_sections(lines) do
    split_at_sections(lines, [], [])
  end

  defp split_at_sections([], preamble_acc, sections_acc) do
    {Enum.reverse(preamble_acc), Enum.reverse(sections_acc)}
  end

  defp split_at_sections([line | rest], preamble_acc, []) do
    case extract_heading(line) do
      {:ok, heading} ->
        {section_lines, remaining} = collect_section_lines([line], rest)
        split_at_sections(remaining, preamble_acc, [{heading, section_lines}])

      :not_heading ->
        split_at_sections(rest, [line | preamble_acc], [])
    end
  end

  defp split_at_sections([line | rest], preamble_acc, sections_acc) do
    case extract_heading(line) do
      {:ok, heading} ->
        {section_lines, remaining} = collect_section_lines([line], rest)
        split_at_sections(remaining, preamble_acc, [{heading, section_lines} | sections_acc])

      :not_heading ->
        # This shouldn't happen since after first section, all lines belong to sections
        # But handle gracefully by appending to last section
        [{prev_heading, prev_lines} | rest_sections] = sections_acc
        split_at_sections(rest, preamble_acc, [{prev_heading, prev_lines ++ [line]} | rest_sections])
    end
  end

  # Collect lines belonging to a section (until next ## heading or EOF)
  defp collect_section_lines(acc, []) do
    {Enum.reverse(acc), []}
  end

  defp collect_section_lines(acc, [line | rest] = remaining) do
    case extract_heading(line) do
      {:ok, _heading} ->
        {Enum.reverse(acc), remaining}

      :not_heading ->
        collect_section_lines([line | acc], rest)
    end
  end

  # Check if a line is a ## heading (but not ### or deeper)
  defp extract_heading("## " <> heading_text), do: {:ok, String.trim_trailing(heading_text)}
  defp extract_heading(_), do: :not_heading

  # Truncate preamble string to fit within @max_preamble_bytes on a line boundary
  defp truncate_preamble_string(preamble) when byte_size(preamble) <= @max_preamble_bytes do
    preamble
  end

  defp truncate_preamble_string(preamble) do
    lines = String.split(preamble, "\n", trim: false)
    truncate_lines_to_bytes(lines, @max_preamble_bytes)
  end

  # Take lines until adding the next line would exceed the byte limit
  defp truncate_lines_to_bytes(lines, max_bytes) do
    truncate_lines_to_bytes(lines, max_bytes, [], 0)
  end

  defp truncate_lines_to_bytes([], _max_bytes, acc, _size) do
    Enum.reverse(acc) |> Enum.join("\n")
  end

  defp truncate_lines_to_bytes([line | rest], max_bytes, acc, current_size) do
    # Account for the newline separator between lines
    separator_size = if acc == [], do: 0, else: 1
    new_size = current_size + separator_size + byte_size(line)

    if new_size > max_bytes do
      Enum.reverse(acc) |> Enum.join("\n")
    else
      truncate_lines_to_bytes(rest, max_bytes, [line | acc], new_size)
    end
  end

  # Drop oldest sections (from front) until total fits within target bytes.
  # When no sections remain, return [] — preamble is always preserved as-is.
  defp drop_oldest_until_fits(_preamble, [], _target), do: []

  defp drop_oldest_until_fits(preamble, sections, target) do
    total = byte_size(reassemble(preamble, sections))

    if total <= target do
      sections
    else
      drop_oldest_until_fits(preamble, tl(sections), target)
    end
  end

  # Reassemble preamble and sections into a single string
  defp reassemble(preamble, []) do
    preamble
  end

  defp reassemble("", sections) do
    sections
    |> Enum.map(& &1.body)
    |> Enum.join("\n")
  end

  defp reassemble(preamble, sections) do
    section_text =
      sections
      |> Enum.map(& &1.body)
      |> Enum.join("\n")

    preamble <> "\n" <> section_text
  end

  # --- Private helpers ---

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  # Extract members from a team struct or map
  defp extract_members(%{members: members}) when is_list(members), do: members
  defp extract_members(%{"members" => members}) when is_list(members), do: members
  defp extract_members(_), do: []

  # Extract skills from a team struct or map
  defp extract_skills(%{skills: skills}) when is_list(skills), do: skills
  defp extract_skills(%{"skills" => skills}) when is_list(skills), do: skills
  defp extract_skills(_), do: []

  # Extract knowledge from a team struct or map
  defp extract_knowledge(%{knowledge: k}), do: k
  defp extract_knowledge(%{"knowledge" => k}), do: k
  defp extract_knowledge(_), do: nil

  # Sort keys for members and skills
  defp member_sort_key(%{name: name}), do: name || ""
  defp member_sort_key(%{"name" => name}), do: name || ""
  defp member_sort_key(_), do: ""

  defp skill_sort_key(%{"id" => id}), do: id || ""
  defp skill_sort_key(%{id: id}), do: id || ""
  defp skill_sort_key(_), do: ""

  # Canonicalize a member into a sorted-key map with nil/empty values omitted
  defp canonicalize_member(member) do
    skills = get_field(member, :skills, "skills")
    sorted_skills = if is_list(skills) and skills != [], do: Enum.sort(skills), else: skills

    [
      {"name", get_field(member, :name, "name")},
      {"role", get_field(member, :role, "role")},
      {"skills", sorted_skills},
      {"soul", get_field(member, :soul, "soul")}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == [] end)
    |> Enum.sort_by(fn {k, _v} -> k end)
  end

  # Canonicalize a skill into a sorted-key map with nil/empty values omitted
  defp canonicalize_skill(skill) do
    globs = get_field(skill, :globs, "globs")
    sorted_globs = if is_list(globs) and globs != [], do: Enum.sort(globs), else: globs

    [
      {"alwaysApply", get_field(skill, :alwaysApply, "alwaysApply")},
      {"body", get_field(skill, :body, "body")},
      {"description", get_field(skill, :description, "description")},
      {"globs", sorted_globs},
      {"id", get_field(skill, :id, "id")},
      {"title", get_field(skill, :title, "title")},
      {"userInvocable", get_field(skill, :userInvocable, "userInvocable")}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == [] end)
    |> Enum.sort_by(fn {k, _v} -> k end)
  end

  # Get a field from either atom-keyed or string-keyed map.
  # Uses explicit nil check instead of || to handle false values correctly.
  defp get_field(map, atom_key, string_key) do
    case Map.get(map, atom_key) do
      nil -> Map.get(map, string_key)
      value -> value
    end
  end

  # Encode a canonical JSON array from a list of sorted key-value pair lists
  defp canonical_json_array(items) do
    encoded =
      items
      |> Enum.map(&canonical_json_object/1)
      |> Enum.join(",")

    "[#{encoded}]"
  end

  # Encode a canonical JSON object from a sorted key-value pair list
  defp canonical_json_object(pairs) do
    encoded =
      pairs
      |> Enum.map(fn {k, v} -> "#{json_encode_string(k)}:#{json_encode_value(v)}" end)
      |> Enum.join(",")

    "{#{encoded}}"
  end

  defp json_encode_value(v) when is_binary(v), do: json_encode_string(v)
  defp json_encode_value(v) when is_boolean(v), do: if(v, do: "true", else: "false")
  defp json_encode_value(v) when is_integer(v), do: Integer.to_string(v)
  defp json_encode_value(v) when is_float(v), do: Float.to_string(v)
  defp json_encode_value(nil), do: "null"

  defp json_encode_value(v) when is_list(v) do
    encoded = Enum.map(v, &json_encode_value/1) |> Enum.join(",")
    "[#{encoded}]"
  end

  defp json_encode_value(v) when is_map(v) do
    encoded =
      v
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map(fn {k, val} -> "#{json_encode_string(to_string(k))}:#{json_encode_value(val)}" end)
      |> Enum.join(",")

    "{#{encoded}}"
  end

  defp json_encode_string(s) do
    # JSON string encoding: escape special characters
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end
end
