import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { validateRelayUrl, detectPlatforms } from "../config.js";

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

  it("returns empty array when no platform directories exist", () => {
    const platforms = detectPlatforms();
    assert.deepEqual(platforms, []);
  });

  it("detects claude-code from ~/.claude directory", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude"), { recursive: true });
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("claude-code"));
  });

  it("detects cursor from .cursor in cwd", () => {
    fs.mkdirSync(path.join(tmpDir, ".cursor"), { recursive: true });
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("cursor"));
  });

  it("detects gemini from .gemini in cwd", () => {
    fs.mkdirSync(path.join(tmpDir, ".gemini"), { recursive: true });
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("gemini"));
  });

  it("detects multiple platforms simultaneously", () => {
    fs.mkdirSync(path.join(tmpDir, ".claude"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir, ".cursor"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir, ".github"), { recursive: true });
    const platforms = detectPlatforms();
    assert.ok(platforms.includes("claude-code"));
    assert.ok(platforms.includes("cursor"));
    assert.ok(platforms.includes("copilot"));
  });
});
