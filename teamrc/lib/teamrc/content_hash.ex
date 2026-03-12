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
