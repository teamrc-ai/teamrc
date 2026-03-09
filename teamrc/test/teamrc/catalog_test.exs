defmodule Teamrc.CatalogTest do
  use ExUnit.Case, async: true

  alias Teamrc.Catalog

  @templates_dir Catalog.templates_dir()

  # ---------------------------------------------------------------------------
  # list_teams
  # ---------------------------------------------------------------------------

  describe "list_teams/0" do
    test "returns a list of team IDs" do
      teams = Catalog.list_teams()
      assert is_list(teams)
      assert length(teams) > 0
    end

    test "includes known teams" do
      teams = Catalog.list_teams()

      for id <- ["fullstack", "backend", "frontend", "security", "custom"] do
        assert id in teams, "Missing team: #{id}"
      end
    end

    test "does not include _index" do
      teams = Catalog.list_teams()
      refute "_index" in teams
    end

    test "discovers all team files on disk" do
      teams = Catalog.list_teams()

      on_disk =
        Path.join(@templates_dir, "teams")
        |> File.ls!()
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))

      for id <- on_disk do
        assert id in teams, "Team #{id} on disk but not discovered"
      end
    end

    test "preserves index ordering for known teams" do
      teams = Catalog.list_teams()
      fullstack_idx = Enum.find_index(teams, &(&1 == "fullstack"))
      custom_idx = Enum.find_index(teams, &(&1 == "custom"))
      assert fullstack_idx < custom_idx, "fullstack should come before custom"
    end
  end

  # ---------------------------------------------------------------------------
  # list_agent_categories
  # ---------------------------------------------------------------------------

  describe "list_agent_categories/0" do
    test "returns categories with agents" do
      categories = Catalog.list_agent_categories()
      assert is_list(categories)
      assert length(categories) > 0

      for cat <- categories do
        assert cat["id"], "Category missing id"
        assert cat["label"], "Category missing label"
        assert is_list(cat["agents"]), "Category missing agents list"
      end
    end

    test "every listed agent has a loadable file" do
      categories = Catalog.list_agent_categories()

      for cat <- categories, name <- cat["agents"] do
        file_path = Path.join([@templates_dir, "agents", "#{name}.yaml"])
        assert File.exists?(file_path), "Agent file missing: #{name}.yaml"
      end
    end

    test "discovers all agent files on disk" do
      categories = Catalog.list_agent_categories()
      listed = Enum.flat_map(categories, & &1["agents"])

      on_disk =
        Path.join(@templates_dir, "agents")
        |> File.ls!()
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))

      for name <- on_disk do
        assert name in listed, "Agent #{name} on disk but not discovered"
      end
    end

    test "has no duplicate agents across categories" do
      categories = Catalog.list_agent_categories()
      all_agents = Enum.flat_map(categories, & &1["agents"])
      assert length(all_agents) == length(Enum.uniq(all_agents)), "Duplicate agents found"
    end
  end

  # ---------------------------------------------------------------------------
  # list_skill_categories
  # ---------------------------------------------------------------------------

  describe "list_skill_categories/0" do
    test "returns categories with skills" do
      categories = Catalog.list_skill_categories()
      assert is_list(categories)
      assert length(categories) > 0

      for cat <- categories do
        assert cat["id"], "Category missing id"
        assert cat["label"], "Category missing label"
        assert is_list(cat["skills"]), "Category missing skills list"
      end
    end

    test "every listed skill has a loadable file" do
      categories = Catalog.list_skill_categories()

      for cat <- categories, id <- cat["skills"] do
        file_path = Path.join([@templates_dir, "skills", "#{id}.yaml"])
        assert File.exists?(file_path), "Skill file missing: #{id}.yaml"
      end
    end

    test "discovers all skill files on disk" do
      categories = Catalog.list_skill_categories()
      listed = Enum.flat_map(categories, & &1["skills"])

      on_disk =
        Path.join(@templates_dir, "skills")
        |> File.ls!()
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))

      for id <- on_disk do
        assert id in listed, "Skill #{id} on disk but not discovered"
      end
    end

    test "has no duplicate skills across categories" do
      categories = Catalog.list_skill_categories()
      all_skills = Enum.flat_map(categories, & &1["skills"])
      assert length(all_skills) == length(Enum.uniq(all_skills)), "Duplicate skills found"
    end
  end

  # ---------------------------------------------------------------------------
  # load_agent
  # ---------------------------------------------------------------------------

  describe "load_agent/1" do
    test "loads an agent with required fields" do
      agent = Catalog.load_agent("frontend-dev")
      assert agent["name"] == "frontend-dev"
      assert agent["role"], "Agent missing role"
      assert agent["category"], "Agent missing category"
      assert agent["soul"], "Agent missing soul"
      assert String.length(agent["soul"]) > 100, "Soul suspiciously short"
    end

    test "raises for nonexistent agent" do
      assert_raise File.Error, fn ->
        Catalog.load_agent("nonexistent-agent-xyz")
      end
    end

    test "all agents on disk parse successfully" do
      on_disk =
        Path.join(@templates_dir, "agents")
        |> File.ls!()
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))

      for name <- on_disk do
        agent = Catalog.load_agent(name)
        assert agent["name"], "Agent #{name} missing name"
        assert agent["role"], "Agent #{name} missing role"
        assert agent["category"], "Agent #{name} missing category"
        assert agent["soul"], "Agent #{name} missing soul"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # load_skill
  # ---------------------------------------------------------------------------

  describe "load_skill/1" do
    test "loads a skill with required fields" do
      skill = Catalog.load_skill("write-tests")
      assert skill["id"] == "write-tests"
      assert skill["title"], "Skill missing title"
      assert skill["category"], "Skill missing category"
      assert skill["body"], "Skill missing body"
    end

    test "raises for nonexistent skill" do
      assert_raise File.Error, fn ->
        Catalog.load_skill("nonexistent-skill-xyz")
      end
    end

    test "all skills on disk parse successfully" do
      on_disk =
        Path.join(@templates_dir, "skills")
        |> File.ls!()
        |> Enum.filter(&(String.ends_with?(&1, ".yaml") and &1 != "_index.yaml"))
        |> Enum.map(&String.replace_suffix(&1, ".yaml", ""))

      for id <- on_disk do
        skill = Catalog.load_skill(id)
        assert skill["id"], "Skill #{id} missing id"
        assert skill["title"], "Skill #{id} missing title"
        assert skill["category"], "Skill #{id} missing category"
        assert skill["body"], "Skill #{id} missing body"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_team
  # ---------------------------------------------------------------------------

  describe "resolve_team/1" do
    test "resolves fullstack team with members and skills" do
      team = Catalog.resolve_team("fullstack")
      assert team.label, "Missing label"
      assert team.description, "Missing description"
      assert team.team_name, "Missing team_name"
      assert length(team.members) > 0, "No members"
      assert length(team.skills) > 0, "No skills"
    end

    test "members have names, roles, and souls" do
      team = Catalog.resolve_team("backend")

      for member <- team.members do
        assert member.name, "Member missing name"
        assert member.role, "Member missing role"
        assert member.soul, "Member missing soul"
      end
    end

    test "skills have ids and bodies" do
      team = Catalog.resolve_team("backend")

      for skill <- team.skills do
        assert skill.id, "Skill missing id"
        assert skill.body, "Skill missing body"
      end
    end

    test "agent skills reference valid skill ids" do
      team = Catalog.resolve_team("fullstack")
      skill_ids = Enum.map(team.skills, & &1.id)

      for member <- team.members, skills = Map.get(member, :skills), skills != nil, sid <- skills do
        assert sid in skill_ids,
               "Agent #{member.name} references unknown skill: #{sid}"
      end
    end

    test "all teams resolve without errors" do
      team_ids = Catalog.list_teams()

      for id <- team_ids do
        team = Catalog.resolve_team(id)
        assert team.label, "Team #{id} missing label"
        assert team.team_name, "Team #{id} missing team_name"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # agent_recommended_skills
  # ---------------------------------------------------------------------------

  describe "agent_recommended_skills/1" do
    test "returns skills for backend-dev from team templates" do
      skills = Catalog.agent_recommended_skills("backend-dev")
      assert is_list(skills)
      assert length(skills) > 0
      assert "write-tests" in skills
    end

    test "returns sorted list" do
      skills = Catalog.agent_recommended_skills("backend-dev")
      assert skills == Enum.sort(skills)
    end

    test "returns empty list for unknown agent" do
      assert Catalog.agent_recommended_skills("nonexistent-agent-xyz") == []
    end

    test "all recommended skills exist in the skill catalog" do
      categories = Catalog.list_agent_categories()
      all_agents = Enum.flat_map(categories, & &1["agents"])

      for name <- all_agents do
        for skill_id <- Catalog.agent_recommended_skills(name) do
          assert Catalog.load_skill(skill_id),
                 "Agent #{name} recommends nonexistent skill: #{skill_id}"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-reference integrity
  # ---------------------------------------------------------------------------

  describe "catalog integrity" do
    test "all team agent references exist in the catalog" do
      team_ids = Catalog.list_teams()

      for id <- team_ids do
        team = Catalog.resolve_team(id)

        for member <- team.members do
          assert Catalog.load_agent(member.name),
                 "Team #{id} references nonexistent agent: #{member.name}"
        end
      end
    end

    test "all team skill references exist in the catalog" do
      team_ids = Catalog.list_teams()

      for id <- team_ids do
        team = Catalog.resolve_team(id)

        for skill <- team.skills do
          assert Catalog.load_skill(skill.id),
                 "Team #{id} references nonexistent skill: #{skill.id}"
        end
      end
    end

    test "agent souls contain expected sections" do
      categories = Catalog.list_agent_categories()
      all_agents = Enum.flat_map(categories, & &1["agents"])

      for name <- all_agents do
        agent = Catalog.load_agent(name)
        soul = agent["soul"]
        assert String.contains?(soul, "## Identity"), "Agent #{name} missing Identity section"
        assert String.contains?(soul, "## Expertise"), "Agent #{name} missing Expertise section"

        assert String.contains?(soul, "## Principles"),
               "Agent #{name} missing Principles section"

        assert String.contains?(soul, "## Communication"),
               "Agent #{name} missing Communication section"
      end
    end

    test "no agent souls contain removed sections" do
      categories = Catalog.list_agent_categories()
      all_agents = Enum.flat_map(categories, & &1["agents"])

      for name <- all_agents do
        agent = Catalog.load_agent(name)
        soul = agent["soul"]
        refute String.contains?(soul, "## Workflow"), "Agent #{name} still has Workflow section"

        refute String.contains?(soul, "## Deliverables"),
               "Agent #{name} still has Deliverables section"

        refute String.contains?(soul, "## Success Metrics"),
               "Agent #{name} still has Success Metrics section"
      end
    end
  end
end
