defmodule Teamrc.Catalog do
  @moduledoc "Loads team templates from the YAML catalog."

  @templates_dir Path.expand("../../../templates", __DIR__)

  def templates_dir, do: @templates_dir

  @doc "List team template IDs in display order. Auto-discovers new team files."
  def list_teams do
    on_disk = scan_yaml_dir(Path.join(@templates_dir, "teams"))

    case read_yaml_safe(Path.join(@templates_dir, "teams/_index.yaml")) do
      {:ok, index} ->
        ordered = (index["order"] || []) |> Enum.filter(&(&1 in on_disk))
        new = on_disk -- ordered
        ordered ++ new

      :error ->
        on_disk
    end
  end

  @doc "Load a team template's raw metadata (without resolving agent/skill refs)."
  def load_team_raw(id) do
    read_yaml!(Path.join(@templates_dir, "teams/#{id}.yaml"))
  end

  @doc "Load an agent definition from the catalog."
  def load_agent(name) do
    read_yaml!(Path.join(@templates_dir, "agents/#{name}.yaml"))
  end

  @doc "Load a skill definition from the catalog."
  def load_skill(id) do
    read_yaml!(Path.join(@templates_dir, "skills/#{id}.yaml"))
  end

  @doc "List agent categories with their agent lists. Auto-discovers new agents."
  def list_agent_categories do
    dir = Path.join(@templates_dir, "agents")
    on_disk = scan_yaml_dir(dir) |> MapSet.new()

    categories =
      case read_yaml_safe(Path.join(dir, "_index.yaml")) do
        {:ok, index} ->
          (index["categories"] || [])
          |> Enum.map(fn cat ->
            Map.update!(cat, "agents", fn agents ->
              Enum.filter(agents, &MapSet.member?(on_disk, &1))
            end)
          end)

        :error ->
          []
      end

    categorized =
      categories
      |> Enum.flat_map(& &1["agents"])
      |> MapSet.new()

    uncategorized =
      on_disk
      |> MapSet.difference(categorized)
      |> Enum.reduce(%{}, fn name, acc ->
        case read_yaml_safe(Path.join(dir, "#{name}.yaml")) do
          {:ok, agent} ->
            cat = agent["category"] || "uncategorized"
            Map.update(acc, cat, [name], &[name | &1])

          :error ->
            acc
        end
      end)

    Enum.reduce(uncategorized, categories, fn {cat_id, agents}, cats ->
      case Enum.find_index(cats, &(&1["id"] == cat_id)) do
        nil ->
          cats ++ [%{"id" => cat_id, "label" => cat_id, "agents" => Enum.reverse(agents)}]

        idx ->
          List.update_at(cats, idx, fn cat ->
            Map.update!(cat, "agents", &(&1 ++ Enum.reverse(agents)))
          end)
      end
    end)
  end

  @doc "List skill categories with their skill lists. Auto-discovers new skills."
  def list_skill_categories do
    dir = Path.join(@templates_dir, "skills")
    on_disk = scan_yaml_dir(dir) |> MapSet.new()

    categories =
      case read_yaml_safe(Path.join(dir, "_index.yaml")) do
        {:ok, index} ->
          (index["categories"] || [])
          |> Enum.map(fn cat ->
            Map.update!(cat, "skills", fn skills ->
              Enum.filter(skills, &MapSet.member?(on_disk, &1))
            end)
          end)

        :error ->
          []
      end

    categorized =
      categories
      |> Enum.flat_map(& &1["skills"])
      |> MapSet.new()

    uncategorized =
      on_disk
      |> MapSet.difference(categorized)
      |> Enum.reduce(%{}, fn id, acc ->
        case read_yaml_safe(Path.join(dir, "#{id}.yaml")) do
          {:ok, skill} ->
            cat = skill["category"] || "uncategorized"
            Map.update(acc, cat, [id], &[id | &1])

          :error ->
            acc
        end
      end)

    Enum.reduce(uncategorized, categories, fn {cat_id, skills}, cats ->
      case Enum.find_index(cats, &(&1["id"] == cat_id)) do
        nil ->
          cats ++ [%{"id" => cat_id, "label" => cat_id, "skills" => Enum.reverse(skills)}]

        idx ->
          List.update_at(cats, idx, fn cat ->
            Map.update!(cat, "skills", &(&1 ++ Enum.reverse(skills)))
          end)
      end
    end)
  end

  @doc """
  Resolve a team template into a fully hydrated map with inline agent souls and skill bodies.
  Returns a map matching the shape expected by TeamLive.
  """
  def resolve_team(team_id) do
    team = load_team_raw(team_id)
    agent_skills = team["agentSkills"] || %{}

    members =
      (team["agents"] || [])
      |> Enum.map(fn agent_name ->
        agent = load_agent(agent_name)
        skills = Map.get(agent_skills, agent_name, [])

        base = %{
          name: agent["name"],
          role: agent["role"],
          soul: agent["soul"] || ""
        }

        if skills != [], do: Map.put(base, :skills, skills), else: base
      end)

    skills =
      (team["skills"] || [])
      |> Enum.map(fn skill_id ->
        skill = load_skill(skill_id)

        base = %{id: skill["id"]}
        base = if skill["title"], do: Map.put(base, :title, skill["title"]), else: base
        base = if skill["description"], do: Map.put(base, :description, skill["description"]), else: base
        base = if skill["alwaysApply"], do: Map.put(base, :alwaysApply, true), else: base
        base = if skill["globs"], do: Map.put(base, :globs, skill["globs"]), else: base
        base = if skill["body"], do: Map.put(base, :body, skill["body"]), else: base
        base
      end)

    %{
      label: team["label"],
      description: team["description"],
      icon: team_icon(team_id),
      team_name: team["name"],
      default_platforms: team["defaultPlatforms"] || [],
      members: members,
      skills: skills
    }
  end

  @doc "List all team templates with resolved metadata."
  def list_team_templates do
    list_teams()
    |> Enum.map(fn id -> {id, resolve_team(id)} end)
  end

  # Map team IDs to icons for the web UI
  defp team_icon("fullstack"), do: "code"
  defp team_icon("backend"), do: "server"
  defp team_icon("security"), do: "shield"
  defp team_icon("marketing"), do: "megaphone"
  defp team_icon("research"), do: "book"
  defp team_icon("devops"), do: "cloud"
  defp team_icon("custom"), do: "wrench"
  defp team_icon(_), do: "code"

  defp scan_yaml_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  defp read_yaml!(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
  end

  defp read_yaml_safe(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, YamlElixir.read_from_string!(content)}
      {:error, _} -> :error
    end
  end
end
