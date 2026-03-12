import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { upsertMarkerBlock, removeMarkerBlock } from "../adapters/base.js";

const MARKER_START = "<!-- teamrc:start -->";
const MARKER_END = "<!-- teamrc:end -->";

describe("upsertMarkerBlock", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-marker-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("inserts block into a new (non-existent) file", () => {
    const filePath = path.join(tmpDir, "test.md");
    const block = `${MARKER_START}\nHello\n${MARKER_END}`;

    upsertMarkerBlock(filePath, MARKER_START, MARKER_END, block);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes(MARKER_START));
    assert.ok(content.includes("Hello"));
    assert.ok(content.includes(MARKER_END));
  });

  it("inserts block into an empty file", () => {
    const filePath = path.join(tmpDir, "empty.md");
    fs.writeFileSync(filePath, "");
    const block = `${MARKER_START}\nContent\n${MARKER_END}`;

    upsertMarkerBlock(filePath, MARKER_START, MARKER_END, block);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("Content"));
  });

  it("appends block to existing content when no marker exists", () => {
    const filePath = path.join(tmpDir, "existing.md");
    fs.writeFileSync(filePath, "# Existing Content\n\nSome text here.");
    const block = `${MARKER_START}\nNew block\n${MARKER_END}`;

    upsertMarkerBlock(filePath, MARKER_START, MARKER_END, block);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("# Existing Content"));
    assert.ok(content.includes("New block"));
  });

  it("replaces existing block with updated content", () => {
    const filePath = path.join(tmpDir, "update.md");
    const initial = `Before\n${MARKER_START}\nOld content\n${MARKER_END}\nAfter`;
    fs.writeFileSync(filePath, initial);

    const newBlock = `${MARKER_START}\nNew content\n${MARKER_END}`;
    upsertMarkerBlock(filePath, MARKER_START, MARKER_END, newBlock);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(!content.includes("Old content"));
    assert.ok(content.includes("New content"));
    assert.ok(content.includes("Before"));
    assert.ok(content.includes("After"));
  });

  it("handles multiple different marker blocks in the same file", () => {
    const filePath = path.join(tmpDir, "multi.md");
    const markerA = "<!-- blockA:start -->";
    const markerAEnd = "<!-- blockA:end -->";
    const markerB = "<!-- blockB:start -->";
    const markerBEnd = "<!-- blockB:end -->";

    upsertMarkerBlock(filePath, markerA, markerAEnd, `${markerA}\nBlock A\n${markerAEnd}`);
    upsertMarkerBlock(filePath, markerB, markerBEnd, `${markerB}\nBlock B\n${markerBEnd}`);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("Block A"));
    assert.ok(content.includes("Block B"));
  });

  it("uses newFilePrefix when creating a new file", () => {
    const filePath = path.join(tmpDir, "prefixed.md");
    const block = `${MARKER_START}\nBody\n${MARKER_END}`;

    upsertMarkerBlock(filePath, MARKER_START, MARKER_END, block, "# Header\n\n");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.startsWith("# Header\n\n"));
    assert.ok(content.includes("Body"));
  });
});

describe("removeMarkerBlock", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-marker-rm-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("removes an existing block", () => {
    const filePath = path.join(tmpDir, "remove.md");
    const content = `Before\n${MARKER_START}\nBlock content\n${MARKER_END}\nAfter`;
    fs.writeFileSync(filePath, content);

    const removed = removeMarkerBlock(filePath, MARKER_START, MARKER_END);

    assert.equal(removed, true);
    const updated = fs.readFileSync(filePath, "utf-8");
    assert.ok(!updated.includes(MARKER_START));
    assert.ok(!updated.includes("Block content"));
    assert.ok(updated.includes("Before"));
    assert.ok(updated.includes("After"));
  });

  it("returns false when block does not exist", () => {
    const filePath = path.join(tmpDir, "noblock.md");
    fs.writeFileSync(filePath, "Just plain content");

    const removed = removeMarkerBlock(filePath, MARKER_START, MARKER_END);
    assert.equal(removed, false);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.equal(content, "Just plain content");
  });

  it("returns false when file does not exist", () => {
    const filePath = path.join(tmpDir, "nonexistent.md");
    const removed = removeMarkerBlock(filePath, MARKER_START, MARKER_END);
    assert.equal(removed, false);
  });

  it("deletes file when only block content remains", () => {
    const filePath = path.join(tmpDir, "onlyblock.md");
    fs.writeFileSync(filePath, `${MARKER_START}\nOnly this\n${MARKER_END}`);

    const removed = removeMarkerBlock(filePath, MARKER_START, MARKER_END);

    assert.equal(removed, true);
    assert.ok(!fs.existsSync(filePath), "File should be deleted when empty after removal");
  });

  it("removes block while preserving other blocks", () => {
    const filePath = path.join(tmpDir, "preserve.md");
    const markerA = "<!-- blockA:start -->";
    const markerAEnd = "<!-- blockA:end -->";
    const markerB = "<!-- blockB:start -->";
    const markerBEnd = "<!-- blockB:end -->";

    fs.writeFileSync(
      filePath,
      `${markerA}\nKeep A\n${markerAEnd}\n${markerB}\nRemove B\n${markerBEnd}`,
    );

    removeMarkerBlock(filePath, markerB, markerBEnd);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("Keep A"));
    assert.ok(!content.includes("Remove B"));
  });
});
