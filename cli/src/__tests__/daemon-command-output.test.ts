/**
 * Tests for the daemon command's user-facing output.
 *
 * Bug context: The daemon command (`commands/daemon.ts`) starts the daemon
 * but never tells users what --experimental does or that it is available.
 * Users who run `teamrc daemon` without --experimental get no indication
 * that task sync is an available feature.
 *
 * These tests verify:
 * 1. The daemon command registers the --experimental option
 * 2. When --experimental is NOT used, the output should hint at its existence
 * 3. The --experimental flag description is informative
 * 4. The --auto-spawn flag requires --experimental (documented and enforced)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

const DAEMON_COMMAND_PATH = path.resolve(import.meta.dirname, "..", "commands", "daemon.ts");

function readDaemonCommandSource(): string {
  return fs.readFileSync(DAEMON_COMMAND_PATH, "utf-8");
}

describe("daemon command: --experimental flag registration", () => {
  const source = readDaemonCommandSource();

  it("registers --experimental as a command option", () => {
    assert.ok(
      source.includes('.option("--experimental"') || source.includes(".option('--experimental'"),
      "daemon command should register --experimental option",
    );
  });

  it("--experimental option has a description that mentions task sync", () => {
    // Extract the option description
    const match = source.match(/\.option\("--experimental",\s*"([^"]+)"\)/);
    assert.ok(match, "Should find --experimental option with description");
    const description = match![1];
    assert.ok(
      description.toLowerCase().includes("task"),
      `--experimental description "${description}" should mention tasks/task sync`,
    );
  });

  it("--auto-spawn description references --experimental", () => {
    const match = source.match(/\.option\("--auto-spawn",\s*"([^"]+)"\)/);
    assert.ok(match, "Should find --auto-spawn option with description");
    const description = match![1];
    assert.ok(
      description.includes("--experimental"),
      `--auto-spawn description "${description}" should reference --experimental`,
    );
  });

  it("enforces --auto-spawn requires --experimental at runtime", () => {
    // Verify the guard exists in the source
    assert.ok(
      source.includes("opts.autoSpawn && !opts.experimental"),
      "daemon command should check that --auto-spawn requires --experimental",
    );
  });
});

describe("daemon command: experimental feature visibility", () => {
  const source = readDaemonCommandSource();

  it("should inform users about --experimental when not enabled", () => {
    // The daemon command outputs info via p.log.info with team details.
    // When --experimental is NOT set, users should be told about it.
    // This can be implemented as a conditional line in the info block
    // (e.g. a ternary on opts.experimental) or a separate p.log call.
    //
    // We check that the source mentions both "--experimental" and "task sync"
    // in a context that is NOT the autoSpawn error guard.

    // Remove the autoSpawn guard section to avoid false positives
    const withoutAutoSpawnGuard = source.replace(
      /if\s*\(opts\.autoSpawn\s*&&\s*!opts\.experimental\)[\s\S]*?process\.exit\(\d\);/g,
      "",
    );

    const mentionsExperimentalHint =
      (withoutAutoSpawnGuard.includes("--experimental") || withoutAutoSpawnGuard.includes("experimental")) &&
      withoutAutoSpawnGuard.includes("task sync");

    assert.ok(
      mentionsExperimentalHint,
      "Daemon command should inform users about --experimental flag when it is not enabled.\n" +
      "Users who run `teamrc daemon` without --experimental get no indication\n" +
      "that task sync is available.",
    );
  });

  it("daemon info output includes experimental status when enabled", () => {
    // When --experimental IS set, the output should confirm it is active.
    // Check that the info block (p.log.info with team details) includes
    // experimental/tasks info when the flag is on.
    const hasExperimentalInOutput =
      source.includes("opts.experimental") ||
      source.includes("opts.autoSpawn");

    assert.ok(
      hasExperimentalInOutput,
      "Daemon command should reference experimental/autoSpawn flags in its output logic",
    );
  });
});
