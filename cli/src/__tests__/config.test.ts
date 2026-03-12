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
    const config = { token: "trc_ak_test123" };
    fs.writeFileSync(path.join(dir, "config.json"), JSON.stringify(config));

    const result = loadConfig();
    assert.ok(result);
    assert.equal(result.token, "trc_ak_test123");
  });

  it("strips legacy relay field from config", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    const legacy = { token: "trc_ak_legacy", relay: "http://localhost:4000" };
    fs.writeFileSync(path.join(dir, "config.json"), JSON.stringify(legacy));

    const result = loadConfig();
    assert.ok(result);
    assert.equal(result.token, "trc_ak_legacy");
    assert.equal((result as Record<string, unknown>).relay, undefined);
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
    };

    saveConfig(config);
    const loaded = loadConfig();

    assert.ok(loaded);
    assert.equal(loaded.token, config.token);
  });

  it("does not persist relay field", () => {
    // Even if relay is passed (e.g. from legacy code), it must not be persisted
    saveConfig({ token: "trc_ak_norelay" } as TeamrcConfig);
    const raw = fs.readFileSync(path.join(tmpDir, ".teamrc", "config.json"), "utf-8");
    const parsed = JSON.parse(raw);
    assert.equal(parsed.relay, undefined);
  });

  it("saves and loads config with account info", () => {
    const config: TeamrcConfig = {
      token: "trc_ak_acct",
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
    saveConfig({ token: "trc_ak_perms" });

    const dir = path.join(tmpDir, ".teamrc");
    assert.ok(fs.existsSync(dir));
    const stat = fs.statSync(dir);
    assert.equal(stat.mode & 0o777, 0o700);
  });

  it("creates config file with restricted permissions", () => {
    saveConfig({ token: "trc_ak_perms2" });

    const configPath = path.join(tmpDir, ".teamrc", "config.json");
    assert.ok(fs.existsSync(configPath));
    const stat = fs.statSync(configPath);
    assert.equal(stat.mode & 0o777, 0o600);
  });

  it("overwrites existing config", () => {
    saveConfig({ token: "trc_ak_first" });
    saveConfig({ token: "trc_ak_second" });

    const loaded = loadConfig();
    assert.ok(loaded);
    assert.equal(loaded.token, "trc_ak_second");
  });
});

describe("getRelayUrl", () => {
  let tmpDir: string;
  let origHome: string | undefined;
  let origEnv: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-relay-"));
    origHome = process.env["HOME"];
    process.env["HOME"] = tmpDir;
    origEnv = process.env["TEAMRC_RELAY"];
    delete process.env["TEAMRC_RELAY"];
  });

  afterEach(() => {
    if (origHome !== undefined) {
      process.env["HOME"] = origHome;
    } else {
      delete process.env["HOME"];
    }
    if (origEnv !== undefined) {
      process.env["TEAMRC_RELAY"] = origEnv;
    } else {
      delete process.env["TEAMRC_RELAY"];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
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

  it("returns yamlRelay when no override or env var", () => {
    const result = getRelayUrl(undefined, "https://yaml-relay.example.com");
    assert.equal(result, "https://yaml-relay.example.com");
  });

  it("env var takes precedence over yamlRelay", () => {
    process.env["TEAMRC_RELAY"] = "https://env.example.com";
    const result = getRelayUrl(undefined, "https://yaml-relay.example.com");
    assert.equal(result, "https://env.example.com");
  });

  it("override takes precedence over yamlRelay", () => {
    const result = getRelayUrl("https://override.example.com", "https://yaml-relay.example.com");
    assert.equal(result, "https://override.example.com");
  });

  it("defaults to https://teamrc.ai", () => {
    const result = getRelayUrl();
    assert.equal(result, "https://teamrc.ai");
  });
});
