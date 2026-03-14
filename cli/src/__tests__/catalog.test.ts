import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadAgent,
  loadSkill,
  listTeams,
  listAgentCategories,
  listSkillCategories,
  resolveTeam,
  templateToTeamDefinition,
  agentRecommendedSkills,
} from "../catalog.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATES_DIR = path.resolve(__dirname, "../../../templates");

// ---------------------------------------------------------------------------
// listTeams
// ---------------------------------------------------------------------------

describe("listTeams", () => {
  it("returns an array of team IDs", () => {
    const teams = listTeams();
    assert.ok(Array.isArray(teams));
    assert.ok(teams.length > 0);
  });

  it("includes known teams", () => {
    const teams = listTeams();
    for (const id of ["fullstack", "backend", "frontend", "security", "custom"]) {
      assert.ok(teams.includes(id), `Missing team: ${id}`);
    }
  });

  it("does not include _index", () => {
    const teams = listTeams();
    assert.ok(!teams.includes("_index"));
  });

  it("discovers all team files on disk", () => {
    const teams = listTeams();
    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "teams"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const id of onDisk) {
      assert.ok(teams.includes(id), `Team ${id} on disk but not discovered`);
    }
  });

  it("preserves index ordering for known teams", () => {
    const teams = listTeams();
    const fullstackIdx = teams.indexOf("fullstack");
    const customIdx = teams.indexOf("custom");
    assert.ok(fullstackIdx < customIdx, "fullstack should come before custom");
  });
});

// ---------------------------------------------------------------------------
// listAgentCategories
// ---------------------------------------------------------------------------

describe("listAgentCategories", () => {
  it("returns categories with agents", () => {
    const categories = listAgentCategories();
    assert.ok(Array.isArray(categories));
    assert.ok(categories.length > 0);
    for (const cat of categories) {
      assert.ok(cat.id, "Category missing id");
      assert.ok(cat.label, "Category missing label");
      assert.ok(Array.isArray(cat.agents), "Category missing agents array");
    }
  });

  it("every listed agent has a loadable file", () => {
    const categories = listAgentCategories();
    for (const cat of categories) {
      for (const name of cat.agents) {
        const filePath = path.join(TEMPLATES_DIR, "agents", `${name}.yaml`);
        assert.ok(fs.existsSync(filePath), `Agent file missing: ${name}.yaml`);
      }
    }
  });

  it("discovers all agent files on disk", () => {
    const categories = listAgentCategories();
    const listed = categories.flatMap((c) => c.agents);

    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "agents"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const name of onDisk) {
      assert.ok(listed.includes(name), `Agent ${name} on disk but not discovered`);
    }
  });

  it("has no duplicate agents across categories", () => {
    const categories = listAgentCategories();
    const seen = new Set<string>();
    for (const cat of categories) {
      for (const name of cat.agents) {
        assert.ok(!seen.has(name), `Duplicate agent: ${name}`);
        seen.add(name);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// listSkillCategories
// ---------------------------------------------------------------------------

describe("listSkillCategories", () => {
  it("returns categories with skills", () => {
    const categories = listSkillCategories();
    assert.ok(Array.isArray(categories));
    assert.ok(categories.length > 0);
    for (const cat of categories) {
      assert.ok(cat.id, "Category missing id");
      assert.ok(cat.label, "Category missing label");
      assert.ok(Array.isArray(cat.skills), "Category missing skills array");
    }
  });

  it("every listed skill has a loadable file", () => {
    const categories = listSkillCategories();
    for (const cat of categories) {
      for (const id of cat.skills) {
        const filePath = path.join(TEMPLATES_DIR, "skills", `${id}.yaml`);
        assert.ok(fs.existsSync(filePath), `Skill file missing: ${id}.yaml`);
      }
    }
  });

  it("discovers all skill files on disk", () => {
    const categories = listSkillCategories();
    const listed = categories.flatMap((c) => c.skills);

    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "skills"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const id of onDisk) {
      assert.ok(listed.includes(id), `Skill ${id} on disk but not discovered`);
    }
  });

  it("has no duplicate skills across categories", () => {
    const categories = listSkillCategories();
    const seen = new Set<string>();
    for (const cat of categories) {
      for (const id of cat.skills) {
        assert.ok(!seen.has(id), `Duplicate skill: ${id}`);
        seen.add(id);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// loadAgent
// ---------------------------------------------------------------------------

describe("loadAgent", () => {
  it("loads an agent with required fields", () => {
    const agent = loadAgent("frontend-dev");
    assert.equal(agent.name, "frontend-dev");
    assert.ok(agent.role, "Agent missing role");
    assert.ok(agent.category, "Agent missing category");
    assert.ok(agent.soul, "Agent missing soul");
    assert.ok(agent.soul.length > 100, "Soul suspiciously short");
  });

  it("throws for nonexistent agent", () => {
    assert.throws(() => loadAgent("nonexistent-agent-xyz"));
  });

  it("all agents on disk parse successfully", () => {
    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "agents"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const name of onDisk) {
      const agent = loadAgent(name);
      assert.ok(agent.name, `Agent ${name} missing name`);
      assert.ok(agent.role, `Agent ${name} missing role`);
      assert.ok(agent.category, `Agent ${name} missing category`);
      assert.ok(agent.soul, `Agent ${name} missing soul`);
    }
  });

  it("all agents have capability-based descriptions", () => {
    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "agents"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const name of onDisk) {
      const agent = loadAgent(name);
      assert.ok(agent.description, `Agent ${name} missing description`);
      assert.ok(agent.description.length > 20, `Agent ${name} description too short`);
      assert.ok(agent.description.includes("Use when"), `Agent ${name} description missing 'Use when' trigger phrase`);
    }
  });
});

// ---------------------------------------------------------------------------
// loadSkill
// ---------------------------------------------------------------------------

describe("loadSkill", () => {
  it("loads a skill with required fields", () => {
    const skill = loadSkill("write-tests");
    assert.equal(skill.id, "write-tests");
    assert.ok(skill.title, "Skill missing title");
    assert.ok(skill.category, "Skill missing category");
    assert.ok(skill.body, "Skill missing body");
  });

  it("throws for nonexistent skill", () => {
    assert.throws(() => loadSkill("nonexistent-skill-xyz"));
  });

  it("all skills on disk parse successfully", () => {
    const onDisk = fs
      .readdirSync(path.join(TEMPLATES_DIR, "skills"))
      .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
      .map((f) => f.replace(/\.yaml$/, ""));

    for (const id of onDisk) {
      const skill = loadSkill(id);
      assert.ok(skill.id, `Skill ${id} missing id`);
      assert.ok(skill.title, `Skill ${id} missing title`);
      assert.ok(skill.category, `Skill ${id} missing category`);
      assert.ok(skill.body, `Skill ${id} missing body`);
    }
  });
});

// ---------------------------------------------------------------------------
// resolveTeam
// ---------------------------------------------------------------------------

describe("resolveTeam", () => {
  it("resolves fullstack team with members and skills", () => {
    const team = resolveTeam("fullstack");
    assert.ok(team.label, "Missing label");
    assert.ok(team.description, "Missing description");
    assert.ok(team.teamName, "Missing teamName");
    assert.ok(team.members.length > 0, "No members");
    assert.ok(team.skills.length > 0, "No skills");
  });

  it("members have names, roles, and souls", () => {
    const team = resolveTeam("backend");
    for (const member of team.members) {
      assert.ok(member.name, "Member missing name");
      assert.ok(member.role, "Member missing role");
      assert.ok(member.soul, "Member missing soul");
    }
  });

  it("members have descriptions from catalog", () => {
    const team = resolveTeam("fullstack");
    for (const member of team.members) {
      assert.ok(member.description, `Member ${member.name} missing description`);
      assert.ok(member.description!.includes("Use when"), `Member ${member.name} description missing trigger phrase`);
    }
  });

  it("skills have ids and bodies", () => {
    const team = resolveTeam("backend");
    for (const skill of team.skills) {
      assert.ok(skill.id, "Skill missing id");
      assert.ok(skill.body, "Skill missing body");
    }
  });

  it("agent skills reference valid skill ids", () => {
    const team = resolveTeam("fullstack");
    const skillIds = team.skills.map((s) => s.id);
    for (const member of team.members) {
      if (member.skills) {
        for (const sid of member.skills) {
          assert.ok(skillIds.includes(sid), `Agent ${member.name} references unknown skill: ${sid}`);
        }
      }
    }
  });

  it("all teams resolve without errors", () => {
    const teamIds = listTeams();
    for (const id of teamIds) {
      const team = resolveTeam(id);
      assert.ok(team.label, `Team ${id} missing label`);
      assert.ok(team.teamName, `Team ${id} missing teamName`);
    }
  });
});

// ---------------------------------------------------------------------------
// templateToTeamDefinition
// ---------------------------------------------------------------------------

describe("templateToTeamDefinition", () => {
  it("converts template to team definition", () => {
    const template = resolveTeam("backend");
    const def = templateToTeamDefinition(template, "my-project");
    assert.equal(def.name, "my-project");
    assert.ok(def.members.length > 0);
    for (const m of def.members) {
      assert.ok(m.name);
      assert.ok(m.role);
      assert.ok(m.soul);
    }
  });

  it("includes skills when present", () => {
    const template = resolveTeam("fullstack");
    const def = templateToTeamDefinition(template, "test");
    assert.ok(def.skills, "Missing skills");
    assert.ok(def.skills!.length > 0);
  });

  it("preserves descriptions from template", () => {
    const template = resolveTeam("fullstack");
    const def = templateToTeamDefinition(template, "test-desc");
    for (const m of def.members) {
      assert.ok(m.description, `Member ${m.name} missing description in team definition`);
    }
  });

  it("agent members can reference skills by id", () => {
    const template = resolveTeam("fullstack");
    const def = templateToTeamDefinition(template, "test");
    const membersWithSkills = def.members.filter((m) => m.skills && m.skills.length > 0);
    assert.ok(membersWithSkills.length > 0, "No members have skills assigned");
  });
});

// ---------------------------------------------------------------------------
// agentRecommendedSkills
// ---------------------------------------------------------------------------

describe("agentRecommendedSkills", () => {
  it("returns skills for an agent used in team templates", () => {
    // backend-dev appears in fullstack template with write-tests + others
    const skills = agentRecommendedSkills("backend-dev");
    assert.ok(Array.isArray(skills));
    assert.ok(skills.length > 0, "Expected at least one recommended skill for backend-dev");
    assert.ok(skills.includes("write-tests"), "Expected write-tests for backend-dev");
  });

  it("returns empty array for unknown agent", () => {
    const skills = agentRecommendedSkills("nonexistent-agent-xyz");
    assert.deepEqual(skills, []);
  });

  it("returns union across multiple templates", () => {
    // An agent that appears in multiple team templates should get the union
    const skills = agentRecommendedSkills("qa-engineer");
    assert.ok(skills.includes("write-tests"), "Expected write-tests for qa-engineer");
  });

  it("returns no duplicates", () => {
    const skills = agentRecommendedSkills("backend-dev");
    const unique = [...new Set(skills)];
    assert.equal(skills.length, unique.length, "Found duplicate skill IDs");
  });
});

// ---------------------------------------------------------------------------
// Cross-reference integrity
// ---------------------------------------------------------------------------

describe("catalog integrity", () => {
  it("all team agent references exist in the catalog", () => {
    const teamIds = listTeams();
    for (const id of teamIds) {
      const team = resolveTeam(id);
      for (const member of team.members) {
        assert.doesNotThrow(
          () => loadAgent(member.name),
          `Team ${id} references nonexistent agent: ${member.name}`,
        );
      }
    }
  });

  it("all team skill references exist in the catalog", () => {
    const teamIds = listTeams();
    for (const id of teamIds) {
      const team = resolveTeam(id);
      for (const skill of team.skills) {
        assert.doesNotThrow(
          () => loadSkill(skill.id),
          `Team ${id} references nonexistent skill: ${skill.id}`,
        );
      }
    }
  });

  it("agent souls contain expected sections", () => {
    const categories = listAgentCategories();
    const allAgents = categories.flatMap((c) => c.agents);
    for (const name of allAgents) {
      const agent = loadAgent(name);
      assert.ok(agent.soul.includes("## Identity"), `Agent ${name} missing Identity section`);
      assert.ok(agent.soul.includes("## Expertise"), `Agent ${name} missing Expertise section`);
      assert.ok(agent.soul.includes("## Principles"), `Agent ${name} missing Principles section`);
      assert.ok(agent.soul.includes("## Communication"), `Agent ${name} missing Communication section`);
    }
  });

  it("no agent souls contain removed sections", () => {
    const categories = listAgentCategories();
    const allAgents = categories.flatMap((c) => c.agents);
    for (const name of allAgents) {
      const agent = loadAgent(name);
      assert.ok(!agent.soul.includes("## Workflow"), `Agent ${name} still has Workflow section`);
      assert.ok(!agent.soul.includes("## Deliverables"), `Agent ${name} still has Deliverables section`);
      assert.ok(!agent.soul.includes("## Success Metrics"), `Agent ${name} still has Success Metrics section`);
    }
  });
});
