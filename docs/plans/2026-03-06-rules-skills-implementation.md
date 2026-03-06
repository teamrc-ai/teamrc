# Rules & Skills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the Team YAML schema with rules and skills, then map them to platform-native formats for Claude Code, OpenClaw, Cursor, Codex, and Gemini CLI.

**Architecture:** Add `Rule` and `Skill` types to the shared type system. Extend the YAML loader to parse them (backward-compatible). Add resolver functions that dereference agent rule/skill references. Update each platform adapter to inject resolved rules/skills into native format.

**Tech Stack:** TypeScript, Node.js test runner, `yaml` npm package. Tests use `node:test` + `node:assert/strict`. Run with `tsx --test`.

---

### Task 1: Extend Types

**Files:**
- Modify: `cli/src/adapters/base.ts:23-32`

**Step 1: Write the failing test**

Create `cli/src/__tests__/types.test.ts`:

```ts
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import type { Rule, Skill, TeamDefinition } from "../adapters/base.js";

describe("extended types", () => {
  it("TeamDefinition accepts rules and skills", () => {
    const team: TeamDefinition = {
      name: "test-team",
      members: [{ name: "agent-a", role: "coder" }],
      rules: [
        { id: "rule_style", body: "Use prettier." },
        { id: "rule_security", title: "Security", globs: ["*.ts"], alwaysApply: true, body: "Validate all inputs." },
      ],
      skills: [
        { id: "skill_search", description: "Search code" },
        { id: "skill_deploy", title: "Deploy", description: "Deploy to prod", body: "Run npm deploy." },
      ],
    };

    assert.equal(team.rules!.length, 2);
    assert.equal(team.skills!.length, 2);
    assert.equal(team.rules![1].globs![0], "*.ts");
  });

  it("TeamDefinition works without rules and skills (backward compat)", () => {
    const team: TeamDefinition = {
      name: "old-team",
      members: [{ name: "agent-b", role: "reviewer" }],
    };

    assert.equal(team.rules, undefined);
    assert.equal(team.skills, undefined);
  });

  it("agent members can reference rules and skills by id", () => {
    const team: TeamDefinition = {
      name: "ref-team",
      members: [{
        name: "arch",
        role: "architect",
        rules: ["rule_style"],
        skills: ["skill_search"],
      }],
    };

    assert.deepEqual(team.members[0].rules, ["rule_style"]);
    assert.deepEqual(team.members[0].skills, ["skill_search"]);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/types.test.ts`
Expected: FAIL — `Rule`, `Skill` types don't exist; `TeamDefinition` doesn't have `rules`/`skills`

**Step 3: Write the implementation**

In `cli/src/adapters/base.ts`, add these interfaces and extend existing ones:

```ts
// Add after TeamMember interface (line ~27):

export interface Rule {
  id: string;
  title?: string;
  globs?: string[];
  alwaysApply?: boolean;
  body: string | { source: string };
}

export interface Skill {
  id: string;
  title?: string;
  description?: string;
  body?: string | { source: string };
}
```

Then extend `TeamMember` to add optional rule/skill references:

```ts
export interface TeamMember {
  name: string;
  role: string;
  soul?: string;
  rules?: string[];   // references Rule.id
  skills?: string[];  // references Skill.id
}
```

Then extend `TeamDefinition`:

```ts
export interface TeamDefinition {
  name: string;
  members: TeamMember[];
  rules?: Rule[];
  skills?: Skill[];
}
```

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/types.test.ts`
Expected: PASS (3 tests)

**Step 5: Run ALL existing tests to verify no regressions**

Run: `cd cli && npm test`
Expected: All 26+ tests PASS (new fields are optional, so nothing breaks)

**Step 6: Commit**

```bash
git add cli/src/adapters/base.ts cli/src/__tests__/types.test.ts
git commit -m "feat: add Rule and Skill types to TeamDefinition"
```

---

### Task 2: Update YAML Loader

**Files:**
- Modify: `cli/src/team-yaml.ts`
- Modify: `cli/src/__tests__/team-yaml.test.ts`

**Step 1: Write the failing tests**

Add to the end of `cli/src/__tests__/team-yaml.test.ts`, inside a new describe block:

```ts
describe("readTeamYaml with rules and skills", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-yaml-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("parses rules from YAML", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
rules:
  - id: rule_style
    title: Code Style
    body: "Use prettier."
  - id: rule_security
    globs:
      - "*.ts"
    alwaysApply: true
    body: "Validate all inputs."
`;
    const filePath = path.join(tmpDir, "agent-team.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.rules!.length, 2);
    assert.equal(result.rules![0].id, "rule_style");
    assert.equal(result.rules![0].title, "Code Style");
    assert.equal(result.rules![0].body, "Use prettier.");
    assert.deepEqual(result.rules![1].globs, ["*.ts"]);
    assert.equal(result.rules![1].alwaysApply, true);
  });

  it("parses skills from YAML", () => {
    const yaml = `name: my-team
members:
  - name: coder
    role: write code
skills:
  - id: skill_search
    description: Search the codebase
  - id: skill_deploy
    title: Deploy
    description: Deploy to production
    body: "Run npm deploy."
`;
    const filePath = path.join(tmpDir, "agent-team.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 2);
    assert.equal(result.skills![0].id, "skill_search");
    assert.equal(result.skills![0].description, "Search the codebase");
    assert.equal(result.skills![1].body, "Run npm deploy.");
  });

  it("parses agent rule/skill references", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
    rules:
      - rule_style
    skills:
      - skill_search
rules:
  - id: rule_style
    body: "Use prettier."
skills:
  - id: skill_search
    description: Search code
`;
    const filePath = path.join(tmpDir, "agent-team.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.members[0].rules, ["rule_style"]);
    assert.deepEqual(result.members[0].skills, ["skill_search"]);
  });

  it("works without rules or skills (backward compat)", () => {
    const yaml = `name: old-team
members:
  - name: agent
    role: helper
`;
    const filePath = path.join(tmpDir, "agent-team.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.rules, []);
    assert.deepEqual(result.skills, []);
  });

  it("roundtrips rules and skills through write/read", () => {
    const filePath = path.join(tmpDir, "agent-team.yaml");
    const team = {
      name: "roundtrip-team",
      members: [{ name: "agent-a", role: "role-a", rules: ["rule_x"], skills: ["skill_y"] }],
      rules: [{ id: "rule_x", body: "Do X." }],
      skills: [{ id: "skill_y", description: "Does Y" }],
    };

    writeTeamYaml(filePath, team);
    const result = readTeamYaml(filePath);

    assert.ok(result);
    assert.equal(result.rules!.length, 1);
    assert.equal(result.rules![0].id, "rule_x");
    assert.equal(result.skills!.length, 1);
    assert.equal(result.skills![0].id, "skill_y");
    assert.deepEqual(result.members[0].rules, ["rule_x"]);
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd cli && npx tsx --test src/__tests__/team-yaml.test.ts`
Expected: FAIL — readTeamYaml doesn't parse rules/skills, writeTeamYaml doesn't write them

**Step 3: Update readTeamYaml in `cli/src/team-yaml.ts`**

Update the import to include Rule and Skill types:

```ts
import type { TeamDefinition, TeamMember, Rule, Skill } from "./adapters/base.js";
```

After `const members` block (line ~39), add rules/skills parsing. Update the return:

```ts
  const rawRules = data.rules || [];
  const rules: Rule[] = Array.isArray(rawRules)
    ? rawRules.map((r: Record<string, unknown>) => ({
        id: String(r.id || ""),
        ...(r.title ? { title: String(r.title) } : {}),
        ...(r.globs ? { globs: r.globs as string[] } : {}),
        ...(r.alwaysApply !== undefined ? { alwaysApply: Boolean(r.alwaysApply) } : {}),
        body: r.body as string | { source: string },
      }))
    : [];

  const rawSkills = data.skills || [];
  const skills: Skill[] = Array.isArray(rawSkills)
    ? rawSkills.map((s: Record<string, unknown>) => ({
        id: String(s.id || ""),
        ...(s.title ? { title: String(s.title) } : {}),
        ...(s.description ? { description: String(s.description) } : {}),
        ...(s.body !== undefined ? { body: s.body as string | { source: string } } : {}),
      }))
    : [];

  return {
    name: teamName,
    members,
    rules,
    skills,
  };
```

Also update member parsing to include rules/skills references:

```ts
  const members: TeamMember[] = rawMembers.map((m: Record<string, unknown>) => {
    const name = String(m.name || "");
    validateAgentName(name);
    const member: TeamMember = { name, role: String(m.role || "") };
    if (m.soul) member.soul = String(m.soul);
    if (Array.isArray(m.rules)) member.rules = m.rules as string[];
    if (Array.isArray(m.skills)) member.skills = m.skills as string[];
    return member;
  });
```

**Step 4: Update writeTeamYaml in `cli/src/team-yaml.ts`**

```ts
export function writeTeamYaml(filePath: string, team: TeamDefinition): void {
  const data: Record<string, unknown> = {
    name: team.name,
    members: team.members.map((m) => {
      const entry: Record<string, unknown> = { name: m.name, role: m.role };
      if (m.soul) entry.soul = m.soul;
      if (m.rules && m.rules.length > 0) entry.rules = m.rules;
      if (m.skills && m.skills.length > 0) entry.skills = m.skills;
      return entry;
    }),
  };

  if (team.rules && team.rules.length > 0) {
    data.rules = team.rules.map((r) => {
      const entry: Record<string, unknown> = { id: r.id };
      if (r.title) entry.title = r.title;
      if (r.globs) entry.globs = r.globs;
      if (r.alwaysApply !== undefined) entry.alwaysApply = r.alwaysApply;
      entry.body = r.body;
      return entry;
    });
  }

  if (team.skills && team.skills.length > 0) {
    data.skills = team.skills.map((s) => {
      const entry: Record<string, unknown> = { id: s.id };
      if (s.title) entry.title = s.title;
      if (s.description) entry.description = s.description;
      if (s.body) entry.body = s.body;
      return entry;
    });
  }

  const yaml = YAML.stringify(data);
  fs.writeFileSync(filePath, yaml);
}
```

**Step 5: Run tests to verify they pass**

Run: `cd cli && npx tsx --test src/__tests__/team-yaml.test.ts`
Expected: All tests PASS

**Step 6: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add cli/src/team-yaml.ts cli/src/__tests__/team-yaml.test.ts
git commit -m "feat: parse rules and skills from team YAML"
```

---

### Task 3: Add Rule/Skill Resolvers

**Files:**
- Create: `cli/src/resolve-rules.ts`
- Create: `cli/src/__tests__/resolve-rules.test.ts`

**Step 1: Write the failing test**

Create `cli/src/__tests__/resolve-rules.test.ts`:

```ts
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";
import type { TeamDefinition } from "../adapters/base.js";

const team: TeamDefinition = {
  name: "test-team",
  members: [
    { name: "arch", role: "architect", rules: ["rule_style", "rule_security"], skills: ["skill_search"] },
    { name: "coder", role: "coder" },
  ],
  rules: [
    { id: "rule_style", title: "Code Style", body: "Use prettier." },
    { id: "rule_security", body: "Validate all inputs." },
  ],
  skills: [
    { id: "skill_search", description: "Search code", body: "Use grep." },
  ],
};

describe("resolveAgentRules", () => {
  it("resolves referenced rules for an agent", () => {
    const rules = resolveAgentRules(team.members[0], team);
    assert.equal(rules.length, 2);
    assert.equal(rules[0].id, "rule_style");
    assert.equal(rules[0].body, "Use prettier.");
    assert.equal(rules[1].id, "rule_security");
  });

  it("returns empty array when agent has no rules", () => {
    const rules = resolveAgentRules(team.members[1], team);
    assert.deepEqual(rules, []);
  });

  it("skips unknown rule ids", () => {
    const agent = { name: "x", role: "y", rules: ["rule_style", "nonexistent"] };
    const rules = resolveAgentRules(agent, team);
    assert.equal(rules.length, 1);
    assert.equal(rules[0].id, "rule_style");
  });
});

describe("resolveAgentSkills", () => {
  it("resolves referenced skills for an agent", () => {
    const skills = resolveAgentSkills(team.members[0], team);
    assert.equal(skills.length, 1);
    assert.equal(skills[0].id, "skill_search");
    assert.equal(skills[0].body, "Use grep.");
  });

  it("returns empty array when agent has no skills", () => {
    const skills = resolveAgentSkills(team.members[1], team);
    assert.deepEqual(skills, []);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/resolve-rules.test.ts`
Expected: FAIL — module not found

**Step 3: Implement the resolvers**

Create `cli/src/resolve-rules.ts`:

```ts
import type { Rule, Skill, TeamDefinition, TeamMember } from "./adapters/base.js";

export function resolveAgentRules(agent: TeamMember, team: TeamDefinition): Rule[] {
  if (!agent.rules || !team.rules) return [];
  return agent.rules
    .map((id) => team.rules!.find((r) => r.id === id))
    .filter((r): r is Rule => r !== undefined);
}

export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
}
```

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/resolve-rules.test.ts`
Expected: PASS (5 tests)

**Step 5: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add cli/src/resolve-rules.ts cli/src/__tests__/resolve-rules.test.ts
git commit -m "feat: add resolvers for agent rule and skill references"
```

---

### Task 4: Extend Source Resolver for File References

**Files:**
- Modify: `cli/src/resolve-source.ts`
- Modify: `cli/src/__tests__/resolve-source.test.ts`

**Step 1: Write the failing test**

Add to `cli/src/__tests__/resolve-source.test.ts`:

```ts
import { resolveBody } from "../resolve-source.js";

describe("resolveBody", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-resolve-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns string body as-is", () => {
    const result = resolveBody("Use prettier.", tmpDir);
    assert.equal(result, "Use prettier.");
  });

  it("resolves file source reference", () => {
    const rulePath = path.join(tmpDir, "rules", "style.md");
    fs.mkdirSync(path.join(tmpDir, "rules"), { recursive: true });
    fs.writeFileSync(rulePath, "# Style Guide\nUse tabs.");

    const result = resolveBody({ source: "./rules/style.md" }, tmpDir);
    assert.equal(result, "# Style Guide\nUse tabs.");
  });

  it("returns empty string for missing file", () => {
    const result = resolveBody({ source: "./nonexistent.md" }, tmpDir);
    assert.equal(result, "");
  });

  it("returns empty string for undefined body", () => {
    const result = resolveBody(undefined, tmpDir);
    assert.equal(result, "");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/resolve-source.test.ts`
Expected: FAIL — `resolveBody` not exported

**Step 3: Add resolveBody to `cli/src/resolve-source.ts`**

Add imports at the top of the file:

```ts
import * as fs from "node:fs";
import * as path from "node:path";
```

Add the function:

```ts
export function resolveBody(
  body: string | { source: string } | undefined,
  basePath: string,
): string {
  if (body === undefined) return "";
  if (typeof body === "string") return body;
  if (body.source) {
    const resolved = path.resolve(basePath, body.source);
    if (fs.existsSync(resolved)) {
      return fs.readFileSync(resolved, "utf-8");
    }
    return "";
  }
  return "";
}
```

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/resolve-source.test.ts`
Expected: All tests PASS

**Step 5: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add cli/src/resolve-source.ts cli/src/__tests__/resolve-source.test.ts
git commit -m "feat: add resolveBody for file source references in rules/skills"
```

---

### Task 5: Update Claude Code Adapter

**Files:**
- Modify: `cli/src/adapters/claude-code.ts`
- Create: `cli/src/__tests__/claude-code-rules.test.ts`

**Step 1: Write the failing test**

Create `cli/src/__tests__/claude-code-rules.test.ts`:

```ts
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Claude Code agent file with rules and skills", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-cc-rules-"));
    process.env.HOME = tmpDir;
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
    delete process.env.HOME;
  });

  it("includes resolved rules in agent file body", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", rules: ["rule_style"], skills: ["skill_search"] },
      ],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team, "global");

    const agentDir = path.join(tmpDir, ".claude", "agents");
    const files = fs.readdirSync(agentDir).filter((f) => f.startsWith("tb-"));
    assert.equal(files.length, 1);

    const content = fs.readFileSync(path.join(agentDir, files[0]), "utf-8");
    assert.ok(content.includes("## Rules"), "Should have Rules section");
    assert.ok(content.includes("Code Style"), "Should include rule title");
    assert.ok(content.includes("Use prettier."), "Should include rule body");
    assert.ok(content.includes("## Skills"), "Should have Skills section");
    assert.ok(content.includes("Search code"), "Should include skill description");
    assert.ok(content.includes("Use grep."), "Should include skill body");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/claude-code-rules.test.ts`
Expected: FAIL — agent file doesn't include rules/skills sections

**Step 3: Update `buildAgentFile` in `cli/src/adapters/claude-code.ts`**

Add imports:

```ts
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";
```

Update `buildAgentFile` signature to accept optional team, and add rules/skills sections before teammates:

```ts
function buildAgentFile(teamName: string, member: TeamMember, allMembers: TeamMember[], team?: TeamDefinition): string {
  // ... existing name, safeRole, safeTeamName, body, teammates code ...

  let rulesSection = "";
  if (team) {
    const resolvedRules = resolveAgentRules(member, team);
    if (resolvedRules.length > 0) {
      const ruleBlocks = resolvedRules.map((r) => {
        const title = r.title || r.id;
        const body = typeof r.body === "string" ? r.body : "";
        return `### ${title}\n\n${body}`;
      }).join("\n\n");
      rulesSection += `\n## Rules\n\n${ruleBlocks}\n`;
    }

    const resolvedSkills = resolveAgentSkills(member, team);
    if (resolvedSkills.length > 0) {
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
        return `### ${title}\n\n${desc}${body}`;
      }).join("\n\n");
      rulesSection += `\n## Skills\n\n${skillBlocks}\n`;
    }
  }

  // Insert rulesSection between body and ## Teammates in the template
  return `---
name: ${name}
description: "${safeRole} on the ${safeTeamName} team. Use when tasks relate to ${safeRole.toLowerCase()}."
model: inherit
---

# Team: ${safeTeamNameText}

${body}
${rulesSection}
## Teammates

${teammates}

## Team Knowledge

Shared findings and decisions are stored in \`.claude/team-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important, append it to that file.
`;
}
```

Update `writeTeam` to pass the full team definition:

```ts
const content = buildAgentFile(team.name, member, team.members, team);
```

Also update `writeAgentFromPortable` — it calls `buildAgentFile` without the team, which is fine (rules/skills won't be rendered for portable sync, only for `writeTeam`).

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/claude-code-rules.test.ts`
Expected: PASS

**Step 5: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add cli/src/adapters/claude-code.ts cli/src/__tests__/claude-code-rules.test.ts
git commit -m "feat: inject rules and skills into Claude Code agent files"
```

---

### Task 6: Update OpenClaw Adapter

**Files:**
- Modify: `cli/src/adapters/openclaw.ts`
- Create: `cli/src/__tests__/openclaw-rules.test.ts`

**Step 1: Write the failing test**

Create `cli/src/__tests__/openclaw-rules.test.ts`:

```ts
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("OpenClaw agent files with rules and skills", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-oc-rules-"));
    process.env.HOME = tmpDir;
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
    delete process.env.HOME;
  });

  it("includes rules and skills in AGENTS.md", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", rules: ["rule_style"], skills: ["skill_search"] },
      ],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const agentsPath = path.join(tmpDir, ".openclaw", "workspaces", "tb-architect", "AGENTS.md");
    assert.ok(fs.existsSync(agentsPath), "AGENTS.md should exist");

    const content = fs.readFileSync(agentsPath, "utf-8");
    assert.ok(content.includes("## Rules"), "Should have Rules section");
    assert.ok(content.includes("Code Style"), "Should include rule title");
    assert.ok(content.includes("Use prettier."), "Should include rule body");
    assert.ok(content.includes("## Skills"), "Should have Skills section");
    assert.ok(content.includes("Search code"), "Should include skill description");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/openclaw-rules.test.ts`
Expected: FAIL — AGENTS.md doesn't include rules/skills

**Step 3: Update `writeNativeAgentFiles` in `cli/src/adapters/openclaw.ts`**

Add import:

```ts
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";
```

Update `writeNativeAgentFiles` to accept optional team and build rules/skills sections:

```ts
private writeNativeAgentFiles(wsDir: string, teamName: string, member: TeamMember, allMembers: TeamMember[], team?: TeamDefinition): void {
  // ... existing SOUL.md code stays the same ...

  // Build rules and skills sections
  let extraSections = "";
  if (team) {
    const resolvedRules = resolveAgentRules(member, team);
    if (resolvedRules.length > 0) {
      const ruleBlocks = resolvedRules.map((r) => {
        const title = r.title || r.id;
        const body = typeof r.body === "string" ? r.body : "";
        return `### ${title}\n\n${body}`;
      }).join("\n\n");
      extraSections += `## Rules\n\n${ruleBlocks}\n\n`;
    }

    const resolvedSkills = resolveAgentSkills(member, team);
    if (resolvedSkills.length > 0) {
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
        return `### ${title}\n\n${desc}${body}`;
      }).join("\n\n");
      extraSections += `## Skills\n\n${skillBlocks}\n\n`;
    }
  }

  // Insert extraSections before ## Team Knowledge in agentsContent
  const agentsContent = [
    `# Team: ${teamName}`,
    "",
    `You are **${safeName}** — ${safeRole}.`,
    "",
    "## Teammates",
    "",
    teammatesList,
    "",
    ...(extraSections ? [extraSections] : []),
    "## Team Knowledge",
    "",
    "Shared findings and decisions are stored in `TEAM-KNOWLEDGE.md` in the default workspace. Read it at the start of every session for context from other agents and machines. When you discover something important, append it to that file.",
    "",
  ].join("\n");
  fs.writeFileSync(agentsPath, agentsContent);
}
```

Update all callers of `writeNativeAgentFiles` to pass team:
- In `writeTeam`: `this.writeNativeAgentFiles(workspaceDir, team.name, member, team.members, team);`
- In `writeAgentFromPortable`: leave as-is (no team context available)

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/openclaw-rules.test.ts`
Expected: PASS

**Step 5: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add cli/src/adapters/openclaw.ts cli/src/__tests__/openclaw-rules.test.ts
git commit -m "feat: inject rules and skills into OpenClaw agent files"
```

---

### Task 7: Add Cursor Adapter

**Files:**
- Create: `cli/src/adapters/cursor.ts`
- Create: `cli/src/__tests__/cursor-rules.test.ts`
- Modify: `cli/src/adapters/base.ts` (register in getAdapter)

**Step 1: Write the failing test**

Create `cli/src/__tests__/cursor-rules.test.ts`:

```ts
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Cursor adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-cursor-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes rules as .mdc files in .cursor/rules/", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      rules: [
        { id: "rule_style", title: "Code Style", globs: ["*.ts"], alwaysApply: false, body: "Use prettier." },
        { id: "rule_security", title: "Security", alwaysApply: true, body: "Validate all inputs." },
      ],
    };

    adapter.writeTeam(team);

    const rulesDir = path.join(tmpDir, ".cursor", "rules");
    assert.ok(fs.existsSync(rulesDir));

    const styleFile = path.join(rulesDir, "tb-rule_style.mdc");
    assert.ok(fs.existsSync(styleFile));

    const content = fs.readFileSync(styleFile, "utf-8");
    assert.ok(content.includes("description: Code Style"));
    assert.ok(content.includes('globs: ["*.ts"]'));
    assert.ok(content.includes("alwaysApply: false"));
    assert.ok(content.includes("Use prettier."));

    const secFile = path.join(rulesDir, "tb-rule_security.mdc");
    const secContent = fs.readFileSync(secFile, "utf-8");
    assert.ok(secContent.includes("alwaysApply: true"));
  });

  it("writes agent instructions to AGENTS.md", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design architecture" },
        { name: "coder", role: "write code" },
      ],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, ".cursor", "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd));
    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("architect"));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/cursor-rules.test.ts`
Expected: FAIL — module not found

**Step 3: Create `cli/src/adapters/cursor.ts`**

```ts
import * as fs from "node:fs";
import * as path from "node:path";
import {
  type PlatformAdapter,
  type TeamDefinition,
  type Rule,
} from "./base.js";

export class CursorAdapter implements PlatformAdapter {
  private cursorDir(): string {
    return path.join(process.cwd(), ".cursor");
  }

  private rulesDir(): string {
    return path.join(this.cursorDir(), "rules");
  }

  private listTbRules(): string[] {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".mdc"));
  }

  readTeam(): TeamDefinition | null {
    return null;
  }

  writeTeam(team: TeamDefinition): void {
    if (team.rules) {
      for (const rule of team.rules) {
        this.writeRuleMdc(rule);
      }
    }
    this.writeAgentsMd(team);
  }

  private writeRuleMdc(rule: Rule): void {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const fileName = `tb-${rule.id}.mdc`;
    const filePath = path.join(dir, fileName);

    const description = rule.title || rule.id;
    const globs = rule.globs ? `globs: ${JSON.stringify(rule.globs)}` : "";
    const alwaysApply = rule.alwaysApply !== undefined ? `alwaysApply: ${rule.alwaysApply}` : "alwaysApply: false";
    const body = typeof rule.body === "string" ? rule.body : "";

    const frontmatter = [
      "---",
      `description: ${description}`,
      ...(globs ? [globs] : []),
      alwaysApply,
      "---",
    ].join("\n");

    fs.writeFileSync(filePath, `${frontmatter}\n\n${body}\n`);
  }

  private writeAgentsMd(team: TeamDefinition): void {
    const cursorDir = this.cursorDir();
    if (!fs.existsSync(cursorDir)) fs.mkdirSync(cursorDir, { recursive: true });

    const agentsMdPath = path.join(cursorDir, "AGENTS.md");
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";

    const memberLines = team.members
      .map((m) => `- **${m.name}** — ${m.role}`)
      .join("\n");

    const block = [marker, `# Team: ${team.name}`, "", memberLines, markerEnd].join("\n");

    if (fs.existsSync(agentsMdPath)) {
      let content = fs.readFileSync(agentsMdPath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(agentsMdPath, content);
    } else {
      fs.writeFileSync(agentsMdPath, block + "\n");
    }
  }

  readKnowledge(): string { return ""; }
  writeKnowledge(_content: string): void {}
  appendKnowledge(_entries: string[]): void {}
  getHashes(): Record<string, string> { return {}; }
  installHooks(_relay: string, _token: string): void {}
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const actions: string[] = [];
    const tbRules = this.listTbRules();
    for (const f of tbRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    if (tbRules.length > 0) {
      actions.push(`Deleted ${tbRules.length} TeamBridge cursor rule(s)`);
    }
    return actions;
  }
}
```

Register in `cli/src/adapters/base.ts` `getAdapter` switch statement:

```ts
case "cursor": {
  const mod = require("./cursor.js") as {
    CursorAdapter: new () => PlatformAdapter;
  };
  return new mod.CursorAdapter();
}
```

**Step 4: Run test to verify it passes**

Run: `cd cli && npx tsx --test src/__tests__/cursor-rules.test.ts`
Expected: PASS

**Step 5: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add cli/src/adapters/cursor.ts cli/src/adapters/base.ts cli/src/__tests__/cursor-rules.test.ts
git commit -m "feat: add Cursor adapter with .mdc rule file support"
```

---

### Task 8: Add Codex Adapter

**Files:**
- Create: `cli/src/adapters/codex.ts`
- Create: `cli/src/__tests__/codex-rules.test.ts`
- Modify: `cli/src/adapters/base.ts` (register in getAdapter)

**Step 1: Write the failing test**

Create `cli/src/__tests__/codex-rules.test.ts`:

```ts
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Codex adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-codex-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes team and rules to AGENTS.md", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design", rules: ["rule_style"] }],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd));

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("architect"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/codex-rules.test.ts`
Expected: FAIL

**Step 3: Create `cli/src/adapters/codex.ts`**

```ts
import * as fs from "node:fs";
import * as path from "node:path";
import type { PlatformAdapter, TeamDefinition } from "./base.js";

export class CodexAdapter implements PlatformAdapter {
  private agentsMdPath(): string {
    return path.join(process.cwd(), "AGENTS.md");
  }

  readTeam(): TeamDefinition | null { return null; }

  writeTeam(team: TeamDefinition): void {
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";

    const memberLines = team.members
      .map((m) => `- **${m.name}** — ${m.role}`)
      .join("\n");

    const sections = [`# Team: ${team.name}`, "", memberLines];

    if (team.rules && team.rules.length > 0) {
      sections.push("", "## Rules", "");
      for (const rule of team.rules) {
        const title = rule.title || rule.id;
        const body = typeof rule.body === "string" ? rule.body : "";
        sections.push(`### ${title}`, "", body);
      }
    }

    if (team.skills && team.skills.length > 0) {
      sections.push("", "## Skills", "");
      for (const skill of team.skills) {
        const title = skill.title || skill.id;
        const desc = skill.description || "";
        const body = skill.body ? (typeof skill.body === "string" ? skill.body : "") : "";
        sections.push(`### ${title}`, "", ...(desc ? [desc, ""] : []), ...(body ? [body] : []));
      }
    }

    const block = [marker, ...sections, markerEnd].join("\n");
    const filePath = this.agentsMdPath();

    if (fs.existsSync(filePath)) {
      let content = fs.readFileSync(filePath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(filePath, content);
    } else {
      fs.writeFileSync(filePath, block + "\n");
    }
  }

  readKnowledge(): string { return ""; }
  writeKnowledge(_content: string): void {}
  appendKnowledge(_entries: string[]): void {}
  getHashes(): Record<string, string> { return {}; }
  installHooks(_relay: string, _token: string): void {}
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const filePath = this.agentsMdPath();
    if (!fs.existsSync(filePath)) return [];
    const content = fs.readFileSync(filePath, "utf-8");
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";
    const regex = new RegExp(
      `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
    );
    const cleaned = content.replace(regex, "\n");
    if (cleaned !== content) {
      fs.writeFileSync(filePath, cleaned.trimEnd() + "\n");
      return ["Removed TeamBridge section from AGENTS.md"];
    }
    return [];
  }
}
```

Register in `getAdapter`:

```ts
case "codex": {
  const mod = require("./codex.js") as {
    CodexAdapter: new () => PlatformAdapter;
  };
  return new mod.CodexAdapter();
}
```

**Step 4: Run test, run ALL tests, commit**

```bash
cd cli && npx tsx --test src/__tests__/codex-rules.test.ts
cd cli && npm test
git add cli/src/adapters/codex.ts cli/src/adapters/base.ts cli/src/__tests__/codex-rules.test.ts
git commit -m "feat: add Codex adapter with AGENTS.md rules support"
```

---

### Task 9: Add Gemini CLI Adapter

**Files:**
- Create: `cli/src/adapters/gemini.ts`
- Create: `cli/src/__tests__/gemini-rules.test.ts`
- Modify: `cli/src/adapters/base.ts` (register in getAdapter)

**Step 1: Write the failing test**

Create `cli/src/__tests__/gemini-rules.test.ts`:

```ts
import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Gemini CLI adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-gemini-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes team and rules to GEMINI.md", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    const geminiMd = path.join(tmpDir, "GEMINI.md");
    assert.ok(fs.existsSync(geminiMd));

    const content = fs.readFileSync(geminiMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cli && npx tsx --test src/__tests__/gemini-rules.test.ts`
Expected: FAIL

**Step 3: Create `cli/src/adapters/gemini.ts`**

Same pattern as Codex but writes to `GEMINI.md`:

```ts
import * as fs from "node:fs";
import * as path from "node:path";
import type { PlatformAdapter, TeamDefinition } from "./base.js";

export class GeminiAdapter implements PlatformAdapter {
  private geminiMdPath(): string {
    return path.join(process.cwd(), "GEMINI.md");
  }

  readTeam(): TeamDefinition | null { return null; }

  writeTeam(team: TeamDefinition): void {
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";

    const memberLines = team.members
      .map((m) => `- **${m.name}** — ${m.role}`)
      .join("\n");

    const sections = [`# Team: ${team.name}`, "", memberLines];

    if (team.rules && team.rules.length > 0) {
      sections.push("", "## Rules", "");
      for (const rule of team.rules) {
        const title = rule.title || rule.id;
        const body = typeof rule.body === "string" ? rule.body : "";
        sections.push(`### ${title}`, "", body);
      }
    }

    if (team.skills && team.skills.length > 0) {
      sections.push("", "## Skills", "");
      for (const skill of team.skills) {
        const title = skill.title || skill.id;
        const desc = skill.description || "";
        const body = skill.body ? (typeof skill.body === "string" ? skill.body : "") : "";
        sections.push(`### ${title}`, "", ...(desc ? [desc, ""] : []), ...(body ? [body] : []));
      }
    }

    const block = [marker, ...sections, markerEnd].join("\n");
    const filePath = this.geminiMdPath();

    if (fs.existsSync(filePath)) {
      let content = fs.readFileSync(filePath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(filePath, content);
    } else {
      fs.writeFileSync(filePath, block + "\n");
    }
  }

  readKnowledge(): string { return ""; }
  writeKnowledge(_content: string): void {}
  appendKnowledge(_entries: string[]): void {}
  getHashes(): Record<string, string> { return {}; }
  installHooks(_relay: string, _token: string): void {}
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const filePath = this.geminiMdPath();
    if (!fs.existsSync(filePath)) return [];
    const content = fs.readFileSync(filePath, "utf-8");
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";
    const regex = new RegExp(
      `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
    );
    const cleaned = content.replace(regex, "\n");
    if (cleaned !== content) {
      fs.writeFileSync(filePath, cleaned.trimEnd() + "\n");
      return ["Removed TeamBridge section from GEMINI.md"];
    }
    return [];
  }
}
```

Register in `getAdapter`:

```ts
case "gemini": {
  const mod = require("./gemini.js") as {
    GeminiAdapter: new () => PlatformAdapter;
  };
  return new mod.GeminiAdapter();
}
```

**Step 4: Run test, run ALL tests, commit**

```bash
cd cli && npx tsx --test src/__tests__/gemini-rules.test.ts
cd cli && npm test
git add cli/src/adapters/gemini.ts cli/src/adapters/base.ts cli/src/__tests__/gemini-rules.test.ts
git commit -m "feat: add Gemini CLI adapter with GEMINI.md rules support"
```

---

### Task 10: Update CLI Platform Detection

**Files:**
- Modify: `cli/src/config.ts`
- Modify: `cli/src/index.ts`

**Step 1: Read config.ts to understand detectPlatforms**

Read `cli/src/config.ts` and find the `detectPlatforms` function.

**Step 2: Update `detectPlatforms` to include new platforms**

Add detection logic for cursor (`.cursor/` dir in cwd), codex (`.codex/` dir in home), and gemini (`.gemini/` dir in home or cwd).

**Step 3: Update `requirePlatform` valid list in `cli/src/index.ts`**

```ts
const valid = ["claude-code", "openclaw", "cursor", "codex", "gemini"];
```

**Step 4: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add cli/src/config.ts cli/src/index.ts
git commit -m "feat: add cursor, codex, gemini to platform detection"
```

---

### Task 11: Integration Test

**Files:**
- Create: `cli/src/__tests__/integration-rules.test.ts`

**Step 1: Write an integration test that exercises the full flow**

```ts
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
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-integration-"));
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
    const yamlPath = path.join(tmpDir, "agent-team.yaml");
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
```

**Step 2: Run the integration test**

Run: `cd cli && npx tsx --test src/__tests__/integration-rules.test.ts`
Expected: PASS

**Step 3: Run ALL tests**

Run: `cd cli && npm test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add cli/src/__tests__/integration-rules.test.ts
git commit -m "test: add integration test for rules/skills flow"
```

---

### Task 12: Security Review

**Files:** All files modified/created in Tasks 1-11.

After all implementation is complete, run the following reviews:

**Step 1: Code review** — Run code reviewer agent on all changed files.

**Step 2: Security review** — Specifically check for:
- **RCE**: Ensure `resolveBody` cannot resolve paths outside the project (path traversal). Add validation that resolved paths stay within basePath.
- **BOLA/IDOR**: Ensure rule/skill IDs cannot be used to reference resources from other teams.
- **Injection**: Ensure YAML content cannot inject code into generated markdown files (e.g., frontmatter injection in .mdc files).
- **File system**: Ensure `source:` references cannot read arbitrary files (e.g., `/etc/passwd`).

**Step 3: Red team** — Attempt to:
- Use `source: /etc/passwd` in a rule body
- Use `source: ../../.env` to escape project directory
- Inject YAML frontmatter via rule title/body
- Create rule IDs with path traversal characters

**Step 4: Fix any issues found, re-run all tests**

**Step 5: Commit security hardening**

```bash
git commit -m "security: harden rule/skill resolution against path traversal and injection"
```
