import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { generateKeypair, toToken, saveKeypair, loadKeypair } from "../auth.js";

describe("generateKeypair", () => {
  it("returns an object with publicKey and privateKey as Uint8Arrays", async () => {
    const kp = await generateKeypair();
    assert.ok(kp.publicKey instanceof Uint8Array);
    assert.ok(kp.privateKey instanceof Uint8Array);
  });

  it("publicKey is 32 bytes (ed25519)", async () => {
    const kp = await generateKeypair();
    assert.equal(kp.publicKey.length, 32);
  });

  it("privateKey is 32 bytes", async () => {
    const kp = await generateKeypair();
    assert.equal(kp.privateKey.length, 32);
  });

  it("generates unique keypairs on each call", async () => {
    const kp1 = await generateKeypair();
    const kp2 = await generateKeypair();
    assert.notDeepEqual(kp1.publicKey, kp2.publicKey);
    assert.notDeepEqual(kp1.privateKey, kp2.privateKey);
  });
});

describe("toToken", () => {
  it("returns a string starting with trc_ak_", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);
    assert.ok(token.startsWith("trc_ak_"));
  });

  it("is deterministic for the same keypair", async () => {
    const kp = await generateKeypair();
    const token1 = toToken(kp.publicKey);
    const token2 = toToken(kp.publicKey);
    assert.equal(token1, token2);
  });

  it("produces different tokens for different keypairs", async () => {
    const kp1 = await generateKeypair();
    const kp2 = await generateKeypair();
    assert.notEqual(toToken(kp1.publicKey), toToken(kp2.publicKey));
  });

  it("produces a base64url-encoded token (no +, /, or = chars)", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);
    const encoded = token.slice("trc_ak_".length);
    assert.ok(!encoded.includes("+"), "should not contain +");
    assert.ok(!encoded.includes("/"), "should not contain /");
    assert.ok(!encoded.includes("="), "should not contain =");
  });
});

describe("saveKeypair + loadKeypair roundtrip", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-auth-"));
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

  it("save then load returns matching keypair", async () => {
    const kp = await generateKeypair();
    saveKeypair(kp);
    const loaded = loadKeypair();

    assert.ok(loaded, "loadKeypair should return a keypair");
    assert.deepEqual(loaded.publicKey, kp.publicKey);
    assert.deepEqual(loaded.privateKey, kp.privateKey);
  });

  it("creates .teamrc directory with correct permissions", async () => {
    const kp = await generateKeypair();
    saveKeypair(kp);

    const dir = path.join(tmpDir, ".teamrc");
    assert.ok(fs.existsSync(dir));
    const stat = fs.statSync(dir);
    assert.equal(stat.mode & 0o777, 0o700);
  });

  it("creates key file with restricted permissions", async () => {
    const kp = await generateKeypair();
    saveKeypair(kp);

    const keyPath = path.join(tmpDir, ".teamrc", "key");
    assert.ok(fs.existsSync(keyPath));
    const stat = fs.statSync(keyPath);
    assert.equal(stat.mode & 0o777, 0o600);
  });

  it("toToken of loaded keypair matches toToken of original", async () => {
    const kp = await generateKeypair();
    const originalToken = toToken(kp.publicKey);

    saveKeypair(kp);
    const loaded = loadKeypair()!;
    const loadedToken = toToken(loaded.publicKey);

    assert.equal(loadedToken, originalToken);
  });
});

describe("loadKeypair edge cases", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-auth-"));
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

  it("returns null when key file does not exist", () => {
    const result = loadKeypair();
    assert.equal(result, null);
  });

  it("returns null when key file contains invalid JSON", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "key"), "not valid json{{{");

    const result = loadKeypair();
    assert.equal(result, null);
  });

  it("returns null when key file is empty", () => {
    const dir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "key"), "");

    const result = loadKeypair();
    assert.equal(result, null);
  });
});
