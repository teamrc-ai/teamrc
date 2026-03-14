defmodule Teamrc.Catalog do
  @moduledoc "Loads team templates from the YAML catalog. Caches in ETS."

  @templates_dir Path.expand("../../../templates", __DIR__)
  @ets_table :trc_catalog_cache

  # --- Client API ---

  def templates_dir, do: @templates_dir

  @doc "Reload all templates from disk into ETS. Useful for development."
  def reload do
    ensure_table()
    :ets.delete_all_objects(@ets_table)
    populate_cache()
    :ok
  end

  @doc "List team template IDs in display order. Auto-discovers new team files."
  def list_teams do
    case ets_get(:list_teams) do
      {:ok, val} -> val
      :miss -> compute_and_cache(:list_teams, &do_list_teams/0)
    end
  end

  @doc "Load a team template's raw metadata (without resolving agent/skill refs)."
  def load_team_raw(id) do
    validate_id!(id)

    case ets_get({:team, id}) do
      {:ok, val} -> val
      :miss -> compute_and_cache({:team, id}, fn -> do_read_yaml!(Path.join(@templates_dir, "teams/#{id}.yaml")) end)
    end
  end

  @doc "Load an agent definition from the catalog."
  def load_agent(name) do
    validate_id!(name)

    case ets_get({:agent, name}) do
      {:ok, val} -> val
      :miss -> compute_and_cache({:agent, name}, fn -> do_read_yaml!(Path.join(@templates_dir, "agents/#{name}.yaml")) end)
    end
  end

  @doc "Load a skill definition from the catalog."
  def load_skill(id) do
    validate_id!(id)

    case ets_get({:skill, id}) do
      {:ok, val} -> val
      :miss -> compute_and_cache({:skill, id}, fn -> do_read_yaml!(Path.join(@templates_dir, "skills/#{id}.yaml")) end)
    end
  end

  @doc "List agent categories with their agent lists. Auto-discovers new agents."
  def list_agent_categories do
    case ets_get(:list_agent_categories) do
      {:ok, val} -> val
      :miss -> compute_and_cache(:list_agent_categories, &do_list_agent_categories/0)
    end
  end

  @doc "Returns the union of skill IDs recommended for an agent across all team templates."
  def agent_recommended_skills(agent_name) do
    case ets_get({:agent_recommended_skills, agent_name}) do
      {:ok, val} -> val
      :miss -> compute_and_cache({:agent_recommended_skills, agent_name}, fn -> do_agent_recommended_skills(agent_name) end)
    end
  end

  @doc "List skill categories with their skill lists. Auto-discovers new skills."
  def list_skill_categories do
    case ets_get(:list_skill_categories) do
      {:ok, val} -> val
      :miss -> compute_and_cache(:list_skill_categories, &do_list_skill_categories/0)
    end
  end

  @doc """
  Resolve a team template into a fully hydrated map with inline agent souls and skill bodies.
  Returns a map matching the shape expected by TeamLive.
  """
  def resolve_team(team_id) do
    case ets_get({:resolve_team, team_id}) do
      {:ok, val} -> val
      :miss -> compute_and_cache({:resolve_team, team_id}, fn -> do_resolve_team(team_id) end)
    end
  end

  # --- Private: ETS helpers ---

  defp ensure_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

      ref ->
        ref
    end
  end

  defp ets_get(key) do
    case :ets.whereis(@ets_table) do
      :undefined -> :miss
      _ref ->
        case :ets.lookup(@ets_table, key) do
          [{^key, val}] -> {:ok, val}
          [] -> :miss
        end
    end
  end

  defp compute_and_cache(key, fun) do
    ensure_table()
    val = fun.()
    :ets.insert(@ets_table, {key, val})
    val
  end

  defp populate_cache do
    # Pre-populate the aggregate queries. Individual items are loaded on-demand.
    teams = do_list_teams()
    :ets.insert(@ets_table, {:list_teams, teams})

    # Pre-load all team/agent/skill YAML files
    Enum.each(teams, fn id ->
      team = do_read_yaml!(Path.join(@templates_dir, "teams/#{id}.yaml"))
      :ets.insert(@ets_table, {{:team, id}, team})
    end)

    agents_dir = Path.join(@templates_dir, "agents")
    for name <- scan_yaml_dir(agents_dir) do
      agent = do_read_yaml!(Path.join(agents_dir, "#{name}.yaml"))
      :ets.insert(@ets_table, {{:agent, name}, agent})
    end

    skills_dir = Path.join(@templates_dir, "skills")
    for id <- scan_yaml_dir(skills_dir) do
      skill = do_read_yaml!(Path.join(skills_dir, "#{id}.yaml"))
      :ets.insert(@ets_table, {{:skill, id}, skill})
    end

    # Pre-compute derived results
    agent_cats = do_list_agent_categories()
    :ets.insert(@ets_table, {:list_agent_categories, agent_cats})

    skill_cats = do_list_skill_categories()
    :ets.insert(@ets_table, {:list_skill_categories, skill_cats})

    Enum.each(teams, fn id ->
      resolved = do_resolve_team(id)
      :ets.insert(@ets_table, {{:resolve_team, id}, resolved})
    end)
  rescue
    e ->
      require Logger
      Logger.warning("Catalog cache population failed: #{inspect(e)}")
  end

  # --- Private: validation ---

  defp validate_id!(id) do
    unless Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/, id) do
      raise ArgumentError, "invalid template id: #{inspect(id)}"
    end

    id
  end

  # --- Private: computation (reads from disk) ---

  defp do_list_teams do
    on_disk = scan_yaml_dir(Path.join(@templates_dir, "teams"))

    case do_read_yaml_safe(Path.join(@templates_dir, "teams/_index.yaml")) do
      {:ok, index} ->
        ordered = (index["order"] || []) |> Enum.filter(&(&1 in on_disk))
        new = on_disk -- ordered
        ordered ++ new

      :error ->
        on_disk
    end
  end

  defp do_list_agent_categories do
    dir = Path.join(@templates_dir, "agents")
    on_disk = scan_yaml_dir(dir) |> MapSet.new()

    categories =
      case do_read_yaml_safe(Path.join(dir, "_index.yaml")) do
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
        case do_read_yaml_safe(Path.join(dir, "#{name}.yaml")) do
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

  defp do_agent_recommended_skills(agent_name) do
    do_list_teams()
    |> Enum.reduce(MapSet.new(), fn team_id, acc ->
      team = load_team_raw(team_id)
      agent_skills = team["agentSkills"] || %{}
      skills = Map.get(agent_skills, agent_name, [])
      MapSet.union(acc, MapSet.new(skills))
    end)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp do_list_skill_categories do
    dir = Path.join(@templates_dir, "skills")
    on_disk = scan_yaml_dir(dir) |> MapSet.new()

    categories =
      case do_read_yaml_safe(Path.join(dir, "_index.yaml")) do
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
        case do_read_yaml_safe(Path.join(dir, "#{id}.yaml")) do
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

  defp do_resolve_team(team_id) do
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

        base = if agent["description"], do: Map.put(base, :description, agent["description"]), else: base
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

  defp do_read_yaml!(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
  end

  defp do_read_yaml_safe(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, YamlElixir.read_from_string!(content)}
      {:error, _} -> :error
    end
  end
end
