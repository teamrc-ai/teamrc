import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { loadConfig, saveConfig, getRelayUrl, type TeamrcConfig } from "../config.js";

describe("loadConfig", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-config-"));
    origHome = process.env["HOME"];
    process.env["HOME"] = tmpDir;
  });

  afterEach(() => {
    if (origHome !== undefined) {
      process.env["HOME"] = origHome;
    } else {
      delete process.env["HOME"];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns null for missing config file", () => {
    const result = loadConfig();
    assert.equal(result, null);
  });

  it("returns null for corrupt JSON file", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "config.json"), "{{not json at all!!");

    const result = loadConfig();
    assert.equal(result, null);
  });

  it("returns null for empty file", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "config.json"), "");

    const result = loadConfig();
    assert.equal(result, null);
  });

  it("loads a valid config", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    const config: TeamrcConfig = {
      token: "trc_ak_test123",
      relay: "https://relay.teamrc.dev",
    };
    fs.writeFileSync(path.join(dir, "config.json"), JSON.stringify(config));

    const result = loadConfig();
    assert.ok(result);
    assert.equal(result.token, "trc_ak_test123");
    assert.equal(result.relay, "https://relay.teamrc.dev");
  });
});

describe("saveConfig + loadConfig roundtrip", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-config-"));
    origHome = process.env["HOME"];
    process.env["HOME"] = tmpDir;
  });

  afterEach(() => {
    if (origHome !== undefined) {
      process.env["HOME"] = origHome;
    } else {
      delete process.env["HOME"];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("saves and loads a basic config", () => {
    const config: TeamrcConfig = {
      token: "trc_ak_roundtrip",
      relay: "http://localhost:4000",
    };

    saveConfig(config);
    const loaded = loadConfig();

    assert.ok(loaded);
    assert.equal(loaded.token, config.token);
    assert.equal(loaded.relay, config.relay);
  });

  it("saves and loads config with account info", () => {
    const config: TeamrcConfig = {
      token: "trc_ak_acct",
      relay: "https://relay.example.com",
      account: { email: "user@example.com" },
      machineName: "dev-laptop",
    };

    saveConfig(config);
    const loaded = loadConfig();

    assert.ok(loaded);
    assert.equal(loaded.account?.email, "user@example.com");
    assert.equal(loaded.machineName, "dev-laptop");
  });

  it("creates .teamrc directory with correct permissions", () => {
    saveConfig({ token: "trc_ak_perms", relay: "http://localhost:4000" });

    const dir = path.join(tmpDir, ".teamrc");
    assert.ok(fs.existsSync(dir));
    const stat = fs.statSync(dir);
    assert.equal(stat.mode & 0o777, 0o700);
  });

  it("creates config file with restricted permissions", () => {
    saveConfig({ token: "trc_ak_perms2", relay: "http://localhost:4000" });

    const configPath = path.join(tmpDir, ".teamrc", "config.json");
    assert.ok(fs.existsSync(configPath));
    const stat = fs.statSync(configPath);
    assert.equal(stat.mode & 0o777, 0o600);
  });

  it("overwrites existing config", () => {
    saveConfig({ token: "trc_ak_first", relay: "http://localhost:4000" });
    saveConfig({ token: "trc_ak_second", relay: "https://relay.example.com" });

    const loaded = loadConfig();
    assert.ok(loaded);
    assert.equal(loaded.token, "trc_ak_second");
    assert.equal(loaded.relay, "https://relay.example.com");
  });
});

describe("getRelayUrl", () => {
  let origEnv: string | undefined;

  beforeEach(() => {
    origEnv = process.env["TEAMRC_RELAY"];
    delete process.env["TEAMRC_RELAY"];
  });

  afterEach(() => {
    if (origEnv !== undefined) {
      process.env["TEAMRC_RELAY"] = origEnv;
    } else {
      delete process.env["TEAMRC_RELAY"];
    }
  });

  it("returns override URL when provided", () => {
    const result = getRelayUrl("https://custom.example.com");
    assert.equal(result, "https://custom.example.com");
  });

  it("returns TEAMRC_RELAY env var when set", () => {
    process.env["TEAMRC_RELAY"] = "https://env-relay.example.com";
    const result = getRelayUrl();
    assert.equal(result, "https://env-relay.example.com");
  });

  it("override takes precedence over env var", () => {
    process.env["TEAMRC_RELAY"] = "https://env.example.com";
    const result = getRelayUrl("https://override.example.com");
    assert.equal(result, "https://override.example.com");
  });

  it("defaults to http://localhost:4000", () => {
    const result = getRelayUrl();
    assert.equal(result, "http://localhost:4000");
  });
});
