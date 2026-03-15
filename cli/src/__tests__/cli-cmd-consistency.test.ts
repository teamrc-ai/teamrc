/**
 * Tests that user-facing CLI output uses `cliCmd()` / `CLI_NAME` instead of
 * hardcoded "teamrc" strings, so that messages render correctly when the CLI
 * is invoked via `npx @teamrc/cli`.
 *
 * Bug context: join.ts line 136 uses a hardcoded "teamrc daemon" string in
 * p.outro(), which should be `cliCmd("daemon")` to respect the npx detection
 * logic in utils.ts.
 *
 * Strategy: Static analysis -- read source files and search for patterns
 * that indicate hardcoded "teamrc <subcommand>" in user-facing output
 * (p.outro, p.log.info, p.log.error, p.log.warn, p.log.step, p.note).
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

const COMMANDS_DIR = path.resolve(import.meta.dirname, "..", "commands");

/**
 * Returns all .ts files in the commands directory.
 */
function getCommandFiles(): string[] {
  return fs.readdirSync(COMMANDS_DIR)
    .filter((f) => f.endsWith(".ts"))
    .map((f) => path.join(COMMANDS_DIR, f));
}

/**
 * Finds lines in source code that contain hardcoded "teamrc <subcommand>"
 * strings inside user-facing output functions (p.outro, p.log.*, p.note).
 *
 * Matches patterns like:
 *   p.outro("...teamrc daemon...")
 *   p.log.info("...teamrc apply...")
 *   p.log.error(`...teamrc init...`)
 *
 * Excludes:
 *   - Comments (lines starting with // or *)
 *   - .description() calls (commander metadata, not user-facing runtime output)
 *   - Lines that use cliCmd() or CLI_NAME (correct usage)
 *   - The string "teamrc" alone without a subcommand (e.g., p.intro("teamrc"))
 *   - Strings like "teamrc.ai" or "teamrc.yaml" (not CLI invocations)
 *   - Strings like "@teamrc/cli" (package name references)
 */
function findHardcodedTeamrcInvocations(filePath: string): { line: number; text: string }[] {
  const content = fs.readFileSync(filePath, "utf-8");
  const lines = content.split("\n");
  const results: { line: number; text: string }[] = [];

  // Known subcommands to match against
  const subcommands = [
    "init", "join", "daemon", "apply", "push", "pull", "sync",
    "delete", "login", "status", "whoami", "doctor", "invite",
    "add-member", "remove-member", "dashboard", "task", "claim",
  ];

  // Build a regex that matches "teamrc <subcommand>" but NOT inside cliCmd() calls
  const subcommandPattern = subcommands.join("|");
  const hardcodedPattern = new RegExp(
    `(?<![/@])\\bteamrc\\s+(${subcommandPattern})\\b`,
  );

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    // Skip comments
    if (line.startsWith("//") || line.startsWith("*") || line.startsWith("/*")) continue;

    // Skip .description() calls (commander metadata)
    if (line.includes(".description(")) continue;

    // Skip lines that already use the correct cliCmd() or CLI_NAME pattern
    if (line.includes("cliCmd(") || line.includes("CLI_NAME")) continue;

    // Skip lines that are not user-facing output.
    // We exclude p.intro() because it is used as a UI banner/header
    // (e.g., p.intro("teamrc doctor")) where the branding is intentional,
    // not an instruction to run a command.
    const isUserFacing =
      line.includes("p.outro(") ||
      line.includes("p.log.") ||
      line.includes("p.note(");
    if (!isUserFacing) continue;

    // Check for hardcoded "teamrc <subcommand>"
    if (hardcodedPattern.test(line)) {
      results.push({ line: i + 1, text: lines[i] });
    }
  }

  return results;
}

describe("CLI command consistency: no hardcoded 'teamrc <subcommand>' in user-facing output", () => {
  const commandFiles = getCommandFiles();

  it("found command files to check", () => {
    assert.ok(commandFiles.length > 0, "Should find at least one command file in commands/");
  });

  for (const filePath of commandFiles) {
    const fileName = path.basename(filePath);

    it(`${fileName} should use cliCmd() instead of hardcoded "teamrc <subcommand>"`, () => {
      const violations = findHardcodedTeamrcInvocations(filePath);
      if (violations.length > 0) {
        const details = violations
          .map((v) => `  line ${v.line}: ${v.text.trim()}`)
          .join("\n");
        assert.fail(
          `Found ${violations.length} hardcoded "teamrc <subcommand>" in user-facing output in ${fileName}.\n` +
          `These should use cliCmd("<subcommand>") to support npx invocation.\n` +
          `Violations:\n${details}`,
        );
      }
    });
  }

  // Also check the main utils.ts file itself -- sometimes helpers outside
  // commands/ also produce user-facing output
  it("utils.ts user-facing output should use cliCmd() consistently", () => {
    const utilsPath = path.resolve(import.meta.dirname, "..", "utils.ts");
    if (!fs.existsSync(utilsPath)) return; // skip if not found
    const violations = findHardcodedTeamrcInvocations(utilsPath);
    if (violations.length > 0) {
      const details = violations
        .map((v) => `  line ${v.line}: ${v.text.trim()}`)
        .join("\n");
      assert.fail(
        `Found hardcoded "teamrc <subcommand>" in utils.ts:\n${details}`,
      );
    }
  });
});

describe("cliCmd utility", () => {
  it("cliCmd function is exported from utils.ts", async () => {
    const utils = await import("../utils.js");
    assert.equal(typeof utils.cliCmd, "function");
  });

  it("cliCmd returns a string containing the subcommand", async () => {
    const utils = await import("../utils.js");
    const result = utils.cliCmd("daemon");
    assert.ok(result.includes("daemon"), `Expected "${result}" to contain "daemon"`);
  });

  it("cliCmd includes CLI_NAME prefix", async () => {
    const utils = await import("../utils.js");
    const result = utils.cliCmd("init");
    assert.ok(
      result.startsWith(utils.CLI_NAME),
      `Expected "${result}" to start with CLI_NAME "${utils.CLI_NAME}"`,
    );
  });

  it("CLI_NAME is either 'teamrc' or 'npx @teamrc/cli'", async () => {
    const utils = await import("../utils.js");
    const validNames = ["teamrc", "npx @teamrc/cli"];
    assert.ok(
      validNames.includes(utils.CLI_NAME),
      `CLI_NAME "${utils.CLI_NAME}" should be one of: ${validNames.join(", ")}`,
    );
  });
});
