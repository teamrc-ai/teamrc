import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { validateRelayUrl, detectPlatforms, detectInstalledPlatforms } from "../config.js";

// ---------------------------------------------------------------------------
// validateRelayUrl
// ---------------------------------------------------------------------------

describe("validateRelayUrl", () => {
  it("accepts https://teamrc.ai", () => {
    assert.doesNotThrow(() => validateRelayUrl("https://teamrc.ai"));
  });

  it("accepts http://localhost:4000 (local OK)", () => {
    assert.doesNotThrow(() => validateRelayUrl("http://localhost:4000"));
  });

  it("accepts http://127.0.0.1:4000 (local OK)", () => {
    assert.doesNotThrow(() => validateRelayUrl("http://127.0.0.1:4000"));
  });

  it("rejects http://evil.com (non-local HTTP)", () => {
    assert.throws(
      () => validateRelayUrl("http://evil.com"),
      /HTTP relay URLs are only allowed for local development/,
    );
  });

  it("rejects ftp://teamrc.ai (wrong scheme)", () => {
    assert.throws(
      () => validateRelayUrl("ftp://teamrc.ai"),
      /Relay URL must use http or https/,
    );
  });

  it("rejects empty string", () => {
    assert.throws(
      () => validateRelayUrl(""),
      /Invalid relay URL/,
    );
  });

  it("accepts https with port", () => {
    assert.doesNotThrow(() => validateRelayUrl("https://teamrc.ai:443"));
  });

  it("accepts http://127.0.0.99:3000 (full loopback range)", () => {
    assert.doesNotThrow(() => validateRelayUrl("http://127.0.0.99:3000"));
  });
});

// ---------------------------------------------------------------------------
// detectPlatforms
// ---------------------------------------------------------------------------

describe("detectPlatforms", () => {
  let tmpDir: string;
  let origHome: string | undefined;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-detect-"));
    origHome = process.env["HOME"];
    origCwd = process.cwd();
    process.env["HOME"] = tmpDir;
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    if (origHome !== undefined) {
      process.env["HOME"] = origHome;
    } else {
      delete process.env["HOME"];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns empty array when no trc-* agent files exist", () => {
    const platforms = detectPlatforms();
    assert.deepEqual(platforms, []);
  });

  it("does not detect platform when directory exists but has no trc-* files", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude", "agents"), { recursive: true });
    const platforms = detectPlatforms();
    assert.deepEqual(platforms, []);
  });

  it("detects claude-code from trc-* files in ~/.claude/agents/", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude", "agents"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, ".claude", "agents", "trc-dev.md"), "agent");
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("claude-code"));
  });

  it("detects cursor from trc-* files in .cursor/agents/", () => {
    fs.mkdirSync(path.join(tmpDir, ".cursor", "agents"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, ".cursor", "agents", "trc-dev.md"), "agent");
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("cursor"));
  });

  it("detects gemini from trc-* files in .gemini/agents/", () => {
    fs.mkdirSync(path.join(tmpDir, ".gemini", "agents"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, ".gemini", "agents", "trc-dev.md"), "agent");
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("gemini"));
  });

  it("detects multiple platforms simultaneously", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude", "agents"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, ".claude", "agents", "trc-dev.md"), "agent");
    fs.mkdirSync(path.join(tmpDir, ".cursor", "agents"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, ".cursor", "agents", "trc-dev.md"), "agent");
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("claude-code"));
    assert.ok(platforms.includes("cursor"));
  });

  it("does not falsely detect copilot from .github directory", () => {
    fs.mkdirSync(path.join(tmpDir, ".github"), { recursive: true });
    const platforms = detectPlatforms();
    assert.ok(!platforms.includes("copilot"));
  });
});

describe("detectInstalledPlatforms", () => {
  let tmpDir: string;
  let origHome: string | undefined;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-installed-"));
    origHome = process.env["HOME"];
    origCwd = process.cwd();
    process.env["HOME"] = tmpDir;
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    if (origHome !== undefined) {
      process.env["HOME"] = origHome;
    } else {
      delete process.env["HOME"];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns empty array when no platform directories exist", () => {
    const platforms = detectInstalledPlatforms();
    assert.deepEqual(platforms, []);
  });

  it("detects claude-code from ~/.claude directory", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude"), { recursive: true });
    const platforms = detectInstalledPlatforms();
    assert.ok(platforms.includes("claude-code"));
  });

  it("detects cursor from .cursor in cwd", () => {
    fs.mkdirSync(path.join(tmpDir, ".cursor"), { recursive: true });
    const platforms = detectInstalledPlatforms();
    assert.ok(platforms.includes("cursor"));
  });

  it("does not falsely detect copilot from .github directory", () => {
    fs.mkdirSync(path.join(tmpDir, ".github"), { recursive: true });
    const platforms = detectInstalledPlatforms();
    assert.ok(!platforms.includes("copilot"));
  });
});
