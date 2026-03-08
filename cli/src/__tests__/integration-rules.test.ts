import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { readTeamYaml, writeTeamYaml } from "../team-yaml.js";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";
import { resolveBody } from "../resolve-source.js";

describe("integration: full rules/skills flow", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-integration-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("write YAML -> read -> resolve rules -> resolve body", () => {
    // Create an external rule file
    const rulesDir = path.join(tmpDir, "rules");
    fs.mkdirSync(rulesDir, { recursive: true });
    fs.writeFileSync(path.join(rulesDir, "security.md"), "Always validate user input.");

    // Write team YAML
    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "integration-team",
      members: [
        { name: "arch", role: "architect", rules: ["rule_inline", "rule_file"], skills: ["skill_search"] },
      ],
      rules: [
        { id: "rule_inline", title: "Inline Rule", body: "Use const." },
        { id: "rule_file", title: "File Rule", body: { source: "./rules/security.md" } },
      ],
      skills: [
        { id: "skill_search", description: "Search code", body: "Use grep." },
      ],
    };
    writeTeamYaml(yamlPath, team);

    // Read it back
    const loaded = readTeamYaml(yamlPath);
    assert.ok(loaded);
    assert.equal(loaded.rules!.length, 2);
    assert.equal(loaded.skills!.length, 1);

    // Resolve agent rules
    const agentRules = resolveAgentRules(loaded.members[0], loaded);
    assert.equal(agentRules.length, 2);
    assert.equal(agentRules[0].body, "Use const.");

    // Resolve file-based rule body
    const fileBody = resolveBody(agentRules[1].body, tmpDir);
    assert.equal(fileBody, "Always validate user input.");

    // Resolve skills
    const agentSkills = resolveAgentSkills(loaded.members[0], loaded);
    assert.equal(agentSkills.length, 1);
    assert.equal(agentSkills[0].body, "Use grep.");
  });
});
