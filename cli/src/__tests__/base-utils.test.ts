import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import {
  slugify,
  sanitizeText,
  sanitizeMarkerContent,
  escapeYamlString,
  cleanupSkillDirs,
  listSkillDirIds,
  collectTeamSkillIds,
  deleteKnowledgeFiles,
  knowledgeFileName,
  BUILTIN_SKILL_IDS,
  type TeamDefinition,
} from "../adapters/base.js";

// ---------------------------------------------------------------------------
// slugify
// ---------------------------------------------------------------------------

describe("slugify", () => {
  it("lowercases and converts spaces to hyphens", () => {
    assert.equal(slugify("My Agent Name"), "my-agent-name");
  });

  it("replaces special characters with hyphens", () => {
    assert.equal(slugify("hello@world!"), "hello-world");
  });

  it("collapses multiple hyphens", () => {
    assert.equal(slugify("a--b---c"), "a-b-c");
  });

  it("strips leading and trailing hyphens", () => {
    assert.equal(slugify("-leading-"), "leading");
  });

  it("handles already-slugified strings", () => {
    assert.equal(slugify("already-slugified"), "already-slugified");
  });

  it("handles uppercase with numbers", () => {
    assert.equal(slugify("Agent 007"), "agent-007");
  });

  it("returns empty string for all-special-char input", () => {
    assert.equal(slugify("!!!"), "");
  });
});

// ---------------------------------------------------------------------------
// sanitizeText
// ---------------------------------------------------------------------------

describe("sanitizeText", () => {
  it("strips newlines and replaces with space", () => {
    assert.equal(sanitizeText("line1\nline2"), "line1 line2");
  });

  it("strips carriage returns", () => {
    assert.equal(sanitizeText("line1\r\nline2"), "line1  line2");
  });

  it("trims leading and trailing whitespace", () => {
    assert.equal(sanitizeText("  hello  "), "hello");
  });

  it("handles string with no newlines", () => {
    assert.equal(sanitizeText("plain text"), "plain text");
  });

  it("handles empty string", () => {
    assert.equal(sanitizeText(""), "");
  });
});

// ---------------------------------------------------------------------------
// sanitizeMarkerContent
// ---------------------------------------------------------------------------

describe("sanitizeMarkerContent", () => {
  it("strips HTML comment open sequences", () => {
    assert.equal(sanitizeMarkerContent("before <!-- inject"), "before  inject");
  });

  it("strips HTML comment close sequences", () => {
    assert.equal(sanitizeMarkerContent("inject --> after"), "inject  after");
  });

  it("strips both open and close in same string", () => {
    const result = sanitizeMarkerContent("<!-- evil -->");
    assert.ok(!result.includes("<!--"));
    assert.ok(!result.includes("-->"));
  });

  it("leaves normal content untouched", () => {
    assert.equal(sanitizeMarkerContent("normal text"), "normal text");
  });

  it("handles empty string", () => {
    assert.equal(sanitizeMarkerContent(""), "");
  });
});

// ---------------------------------------------------------------------------
// escapeYamlString
// ---------------------------------------------------------------------------

describe("escapeYamlString", () => {
  it("escapes double quotes", () => {
    assert.equal(escapeYamlString('say "hello"'), 'say \\"hello\\"');
  });

  it("escapes newlines", () => {
    assert.equal(escapeYamlString("line1\nline2"), "line1\\nline2");
  });

  it("escapes backslashes", () => {
    assert.equal(escapeYamlString("path\\to\\file"), "path\\\\to\\\\file");
  });

  it("escapes backslashes before quotes (order matters)", () => {
    const result = escapeYamlString('a\\"b');
    // backslash is escaped first, then quote: a\\\\"b
    assert.equal(result, 'a\\\\\\"b');
  });

  it("leaves plain strings unchanged", () => {
    assert.equal(escapeYamlString("plain text"), "plain text");
  });

  it("handles empty string", () => {
    assert.equal(escapeYamlString(""), "");
  });
});

// ---------------------------------------------------------------------------
// cleanupSkillDirs
// ---------------------------------------------------------------------------

describe("cleanupSkillDirs", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("only removes directories matching the provided skill IDs", () => {
    fs.mkdirSync(path.join(tmpDir, "trc-foo"));
    fs.mkdirSync(path.join(tmpDir, "trc-bar"));
    fs.mkdirSync(path.join(tmpDir, "trc-baz"));

    const count = cleanupSkillDirs(tmpDir, ["foo", "bar"]);

    assert.equal(count, 2);
    assert.ok(!fs.existsSync(path.join(tmpDir, "trc-foo")));
    assert.ok(!fs.existsSync(path.join(tmpDir, "trc-bar")));
    assert.ok(fs.existsSync(path.join(tmpDir, "trc-baz")), "trc-baz should survive");
  });

  it("leaves other teams' trc-* dirs untouched", () => {
    fs.mkdirSync(path.join(tmpDir, "trc-team-a-skill"));
    fs.mkdirSync(path.join(tmpDir, "trc-team-b-skill"));

    cleanupSkillDirs(tmpDir, ["team-a-skill"]);

    assert.ok(!fs.existsSync(path.join(tmpDir, "trc-team-a-skill")));
    assert.ok(fs.existsSync(path.join(tmpDir, "trc-team-b-skill")));
  });

  it("returns 0 when no matching dirs exist", () => {
    fs.mkdirSync(path.join(tmpDir, "trc-other"));
    assert.equal(cleanupSkillDirs(tmpDir, ["nonexistent"]), 0);
    assert.ok(fs.existsSync(path.join(tmpDir, "trc-other")));
  });

  it("returns 0 for empty skill IDs list", () => {
    fs.mkdirSync(path.join(tmpDir, "trc-foo"));
    assert.equal(cleanupSkillDirs(tmpDir, []), 0);
    assert.ok(fs.existsSync(path.join(tmpDir, "trc-foo")));
  });

  it("returns 0 for non-existent directory", () => {
    assert.equal(cleanupSkillDirs("/nonexistent/path", ["foo"]), 0);
  });
});

// ---------------------------------------------------------------------------
// listSkillDirIds
// ---------------------------------------------------------------------------

describe("listSkillDirIds", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns IDs from trc-* directories", () => {
    fs.mkdirSync(path.join(tmpDir, "trc-foo"));
    fs.mkdirSync(path.join(tmpDir, "trc-bar"));
    fs.writeFileSync(path.join(tmpDir, "trc-not-a-dir.txt"), "");

    const ids = listSkillDirIds(tmpDir);
    assert.deepEqual(ids.sort(), ["bar", "foo"]);
  });

  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(listSkillDirIds("/nonexistent/path"), []);
  });

  it("returns empty array when no trc-* dirs exist", () => {
    assert.deepEqual(listSkillDirIds(tmpDir), []);
  });
});

// ---------------------------------------------------------------------------
// deleteKnowledgeFiles
// ---------------------------------------------------------------------------

describe("deleteKnowledgeFiles", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("deletes only the file matching the specific slug", () => {
    fs.writeFileSync(path.join(tmpDir, "knowledge-frontend.md"), "data");
    fs.writeFileSync(path.join(tmpDir, "knowledge-ops.md"), "data");

    const deleted = deleteKnowledgeFiles(tmpDir, "frontend");

    assert.equal(deleted.length, 1);
    assert.ok(!fs.existsSync(path.join(tmpDir, "knowledge-frontend.md")));
    assert.ok(fs.existsSync(path.join(tmpDir, "knowledge-ops.md")));
  });

  it("treats 'team' as a literal slug, not a wildcard", () => {
    fs.writeFileSync(path.join(tmpDir, "knowledge-team.md"), "data");
    fs.writeFileSync(path.join(tmpDir, "knowledge-other.md"), "data");

    const deleted = deleteKnowledgeFiles(tmpDir, "team");

    assert.equal(deleted.length, 1);
    assert.ok(!fs.existsSync(path.join(tmpDir, "knowledge-team.md")));
    assert.ok(fs.existsSync(path.join(tmpDir, "knowledge-other.md")));
  });

  it("deletes nothing when slug is empty", () => {
    fs.writeFileSync(path.join(tmpDir, "knowledge-foo.md"), "data");

    const deleted = deleteKnowledgeFiles(tmpDir, "");

    assert.equal(deleted.length, 0);
    assert.ok(fs.existsSync(path.join(tmpDir, "knowledge-foo.md")));
  });

  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(deleteKnowledgeFiles("/nonexistent/path", "foo"), []);
  });
});

// ---------------------------------------------------------------------------
// knowledgeFileName
// ---------------------------------------------------------------------------

describe("knowledgeFileName", () => {
  it("builds file name from slug", () => {
    assert.equal(knowledgeFileName("my-team"), "knowledge-my-team.md");
  });

  it("falls back to 'team' for empty slug", () => {
    assert.equal(knowledgeFileName(""), "knowledge-team.md");
  });
});

// ---------------------------------------------------------------------------
// collectTeamSkillIds
// ---------------------------------------------------------------------------

describe("collectTeamSkillIds", () => {
  it("returns built-in IDs when team has no skills", () => {
    const team: TeamDefinition = { name: "test", members: [] };
    const ids = collectTeamSkillIds(team);
    assert.deepEqual(ids, [...BUILTIN_SKILL_IDS]);
  });

  it("returns team skill IDs plus built-in IDs", () => {
    const team: TeamDefinition = {
      name: "test",
      members: [],
      skills: [
        { id: "custom-skill", body: "do stuff" },
        { id: "another", body: "more stuff" },
      ],
    };
    const ids = collectTeamSkillIds(team);
    assert.deepEqual(ids, ["custom-skill", "another", ...BUILTIN_SKILL_IDS]);
  });

  it("returns built-in IDs when skills array is empty", () => {
    const team: TeamDefinition = { name: "test", members: [], skills: [] };
    const ids = collectTeamSkillIds(team);
    assert.deepEqual(ids, [...BUILTIN_SKILL_IDS]);
  });
});
