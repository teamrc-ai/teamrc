import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { readTeamYaml, writeTeamYaml } from "../team-yaml.js";
import { resolveAgentSkills } from "../resolve-skills.js";
import { resolveBody } from "../resolve-source.js";

describe("integration: full skills flow", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-integration-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("write YAML -> read -> resolve skills -> resolve body", () => {
    // Create an external skill file
    const skillsDir = path.join(tmpDir, "skill-files");
    fs.mkdirSync(skillsDir, { recursive: true });
    fs.writeFileSync(path.join(skillsDir, "security.md"), "Always validate user input.");

    // Write team YAML
    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "integration-team",
      members: [
        { name: "arch", role: "architect", skills: ["skill_inline", "skill_file", "skill_search"] },
      ],
      skills: [
        { id: "skill_inline", title: "Inline Skill", alwaysApply: true, body: "Use const." },
        { id: "skill_file", title: "File Skill", alwaysApply: true, body: { source: "./skill-files/security.md" } },
        { id: "skill_search", description: "Search code", body: "Use grep." },
      ],
    };
    writeTeamYaml(yamlPath, team);

    // Read it back
    const loaded = readTeamYaml(yamlPath);
    assert.ok(loaded);
    assert.equal(loaded.skills!.length, 3);

    // Resolve agent skills
    const agentSkills = resolveAgentSkills(loaded.members[0], loaded);
    assert.equal(agentSkills.length, 3);
    assert.equal(agentSkills[0].body, "Use const.");
    assert.equal(agentSkills[0].alwaysApply, true);

    // Resolve file-based skill body
    const fileBody = resolveBody(agentSkills[1].body, tmpDir);
    assert.equal(fileBody, "Always validate user input.");

    // On-demand skill
    assert.equal(agentSkills[2].body, "Use grep.");
  });
});
