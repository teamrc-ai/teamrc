import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  createIsolatedEnv,
  runCli,
  testSetup,
  waitForServer,
  readYaml,
  fileExists,
  readFile,
  writeFile,
  listFiles,
  readConfig,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  signedGet,
  signedPost,
  writeYaml,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

describe("platform file generation", () => {
  it("Claude Code agent files contain role description", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-cc-agents");
    try {
      // Init with backend template which has architect, implementer, reviewer, dba
      const initResult = await runCli(
        ["init", "--name", "cc-agents", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Verify agent files exist
      assert.ok(fileExists(env, ".claude/agents/trc-architect.md"), "trc-architect.md should exist");
      assert.ok(fileExists(env, ".claude/agents/trc-implementer.md"), "trc-implementer.md should exist");

      // Read architect file and verify it contains role-related content
      const architectContent = readFile(env, ".claude/agents/trc-architect.md");

      // Should have YAML frontmatter with name and description
      assert.match(architectContent, /^---\n/, "Agent file should start with YAML frontmatter");
      assert.ok(architectContent.includes("trc-architect"), "Agent file should contain name: trc-architect");
      assert.ok(
        architectContent.toLowerCase().includes("architect"),
        `Agent file should mention the architect role.\nContent:\n${architectContent.slice(0, 500)}`,
      );

      // Should have a Team section
      assert.ok(
        architectContent.includes("# Team:"),
        "Agent file should contain '# Team:' header",
      );

      // Should have Teammates section
      assert.ok(
        architectContent.includes("## Teammates"),
        "Agent file should contain '## Teammates' section",
      );
    } finally {
      env.cleanup();
    }
  });

  it("Claude Code rule files for always-apply skills", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-cc-rules");
    try {
      // Init with backend template (has skills including write-tests with alwaysApply: true)
      const initResult = await runCli(
        ["init", "--name", "cc-rules", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // The backend template includes "write-tests" which has alwaysApply: true
      // and "api-first" which also has alwaysApply: true
      // These should be written as .claude/rules/trc-{id}.md files
      const rulesDir = ".claude/rules";
      const ruleFiles = listFiles(env, rulesDir).filter((f) => f.startsWith("trc-") && f.endsWith(".md"));

      assert.ok(
        ruleFiles.length > 0,
        `Should have trc-*.md rule files in ${rulesDir}. Found: ${listFiles(env, rulesDir).join(", ")}`,
      );

      // Find at least one always-apply skill rule (write-tests or api-first)
      const hasWriteTests = ruleFiles.includes("trc-write-tests.md");
      const hasApiFirst = ruleFiles.includes("trc-api-first.md");
      assert.ok(
        hasWriteTests || hasApiFirst,
        `Should have trc-write-tests.md or trc-api-first.md rule. Found: ${ruleFiles.join(", ")}`,
      );

      // Read one and verify it has skill body content
      if (hasWriteTests) {
        const ruleContent = readFile(env, `${rulesDir}/trc-write-tests.md`);
        assert.ok(
          ruleContent.includes("test"),
          `Rule file should contain test-related content.\nContent:\n${ruleContent}`,
        );
      }
    } finally {
      env.cleanup();
    }
  });

  it("Claude Code SKILL.md files for on-demand skills", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-cc-skills");
    try {
      // Create a custom YAML with an on-demand skill (alwaysApply: false, no globs)
      // Use init local then manually add an on-demand skill to YAML and apply
      const initResult = await runCli(
        ["init", "--name", "cc-skills", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // The backend template includes skills like "database-constraints" (alwaysApply: false)
      // and "secrets-management" (alwaysApply: false) which should be written as SKILL.md
      const skillsDir = ".claude/skills";
      const skillDirs = listFiles(env, skillsDir).filter((d) => d.startsWith("trc-"));

      assert.ok(
        skillDirs.length > 0,
        `Should have trc-* skill directories in ${skillsDir}. Found: ${listFiles(env, skillsDir).join(", ")}`,
      );

      // Verify at least one has a SKILL.md inside
      let foundSkillMd = false;
      for (const dir of skillDirs) {
        const skillMdPath = `${skillsDir}/${dir}/SKILL.md`;
        if (fileExists(env, skillMdPath)) {
          foundSkillMd = true;
          const content = readFile(env, skillMdPath);
          // Should have frontmatter
          assert.match(content, /^---\n/, `SKILL.md in ${dir} should start with YAML frontmatter`);
          assert.ok(content.length > 20, `SKILL.md in ${dir} should have meaningful content`);
          break;
        }
      }

      assert.ok(foundSkillMd, `At least one trc-* skill directory should contain a SKILL.md file`);
    } finally {
      env.cleanup();
    }
  });

  it("Cursor agent files in .cursor/agents/", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-cursor-agents");
    try {
      const initResult = await runCli(
        ["init", "--name", "cursor-test", "--team", "backend", "--local", "--platform", "cursor"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Cursor writes agent files to .cursor/agents/trc-{name}.md
      const agentFiles = listFiles(env, ".cursor/agents").filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(
        agentFiles.length > 0,
        `Should have trc-*.md agent files in .cursor/agents/. Found: ${listFiles(env, ".cursor/agents").join(", ")}`,
      );

      // Backend template has architect, implementer, reviewer, dba
      assert.ok(
        agentFiles.includes("trc-architect.md"),
        `Should have trc-architect.md. Found: ${agentFiles.join(", ")}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("Cursor rule files as .mdc in .cursor/rules/", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-cursor-rules");
    try {
      const initResult = await runCli(
        ["init", "--name", "cursor-rules", "--team", "backend", "--local", "--platform", "cursor"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Cursor writes always-apply skills as .mdc files in .cursor/rules/
      const rulesDir = ".cursor/rules";
      const mdcFiles = listFiles(env, rulesDir).filter((f) => f.startsWith("trc-") && f.endsWith(".mdc"));

      assert.ok(
        mdcFiles.length > 0,
        `Should have trc-*.mdc rule files in ${rulesDir}. Found: ${listFiles(env, rulesDir).join(", ")}`,
      );

      // Should have at least write-tests or api-first (both alwaysApply: true in backend template)
      const hasWriteTests = mdcFiles.includes("trc-write-tests.mdc");
      const hasApiFirst = mdcFiles.includes("trc-api-first.mdc");
      assert.ok(
        hasWriteTests || hasApiFirst,
        `Should have trc-write-tests.mdc or trc-api-first.mdc. Found: ${mdcFiles.join(", ")}`,
      );

      // Read one and verify it has .mdc frontmatter
      if (hasWriteTests) {
        const ruleContent = readFile(env, `${rulesDir}/trc-write-tests.mdc`);
        assert.match(ruleContent, /^---\n/, "MDC rule file should start with YAML frontmatter");
        assert.ok(
          ruleContent.includes("test"),
          `MDC rule should contain test-related content.\nContent:\n${ruleContent}`,
        );
      }
    } finally {
      env.cleanup();
    }
  });

  it("global scope files in $HOME/.claude/agents/", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("pf-global-scope");
    try {
      const initResult = await runCli(
        ["init", "--global", "--local", "--name", "global-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Global scope: files should be in $HOME/.claude/agents/ (not project dir)
      const globalAgentsDir = path.join(env.home, ".claude", "agents");
      assert.ok(
        fs.existsSync(globalAgentsDir),
        `Global agents directory ${globalAgentsDir} should exist`,
      );

      const globalFiles = fs.readdirSync(globalAgentsDir).filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(
        globalFiles.length > 0,
        `Should have trc-*.md agent files in global agents dir. Found: ${globalFiles.join(", ")}`,
      );

      // Should NOT have agent files in the project directory
      const projectAgentsDir = path.join(env.projectDir, ".claude", "agents");
      const projectHasFiles = fs.existsSync(projectAgentsDir) &&
        fs.readdirSync(projectAgentsDir).filter((f) => f.startsWith("trc-")).length > 0;
      assert.ok(
        !projectHasFiles,
        "Project .claude/agents/ should NOT have trc-* files when using --global",
      );
    } finally {
      env.cleanup();
    }
  });
});
