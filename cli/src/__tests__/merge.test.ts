import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  mergeKnowledge,
  resolveDefinition,
  resolveChange,
  isKnowledgeKey,
} from "../merge.js";

describe("isKnowledgeKey", () => {
  it("returns true for knowledge keys", () => {
    assert.ok(isKnowledgeKey("knowledge:project"));
    assert.ok(isKnowledgeKey("knowledge:global"));
    assert.ok(isKnowledgeKey("knowledge:team"));
  });

  it("returns false for non-knowledge keys", () => {
    assert.ok(!isKnowledgeKey("team-spec"));
    assert.ok(!isKnowledgeKey("agent:foo"));
  });
});

describe("mergeKnowledge", () => {
  it("keeps local when remote has no new entries", () => {
    const local = "# Knowledge\n- entry one\n- entry two\n";
    const remote = "# Knowledge\n- entry one\n";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "keep-local");
    assert.equal(result.content, local);
  });

  it("appends new remote entries to local", () => {
    const local = "# Knowledge\n- entry one\n";
    const remote = "# Knowledge\n- entry one\n- entry two\n";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "merged");
    assert.ok(result.content.includes("entry one"));
    assert.ok(result.content.includes("entry two"));
  });

  it("deduplicates by content hash", () => {
    const local = "- 2026-01-01: found a bug\n- 2026-01-02: fixed it\n";
    const remote = "- 2026-01-01: found a bug\n- 2026-01-03: new finding\n";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "merged");
    // "found a bug" should not be duplicated
    const matches = result.content.match(/found a bug/g);
    assert.equal(matches?.length, 1);
    assert.ok(result.content.includes("new finding"));
  });

  it("handles both sides adding different entries", () => {
    const local = "- shared entry\n- local only\n";
    const remote = "- shared entry\n- remote only\n";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "merged");
    assert.ok(result.content.includes("local only"));
    assert.ok(result.content.includes("remote only"));
    assert.ok(result.content.includes("shared entry"));
  });

  it("handles empty local", () => {
    const local = "";
    const remote = "- entry one\n";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "merged");
    assert.ok(result.content.includes("entry one"));
  });

  it("handles empty remote", () => {
    const local = "- entry one\n";
    const remote = "";
    const result = mergeKnowledge(local, remote);
    assert.equal(result.action, "keep-local");
  });
});

describe("resolveDefinition", () => {
  it("keeps local when content is identical", () => {
    const content = "name: team\nagents:\n  - name: a\n    role: r\n";
    const result = resolveDefinition(content, { content, updated_at: 100 }, 50);
    assert.equal(result.action, "keep-local");
  });

  it("accepts remote when remote is newer", () => {
    const local = "name: team-v1\nagents: []\n";
    const remote = "name: team-v2\nagents: []\n";
    const result = resolveDefinition(local, { content: remote, updated_at: 200 }, 100);
    assert.equal(result.action, "accept-remote");
    assert.equal(result.content, remote);
  });

  it("keeps local when local is newer", () => {
    const local = "name: team-v2\nagents: []\n";
    const remote = "name: team-v1\nagents: []\n";
    const result = resolveDefinition(local, { content: remote, updated_at: 100 }, 200);
    assert.equal(result.action, "keep-local");
    assert.equal(result.content, local);
  });

  it("accepts remote on tie with warning", () => {
    const local = "name: team-local\n";
    const remote = "name: team-remote\n";
    const result = resolveDefinition(local, { content: remote, updated_at: 100 }, 100);
    assert.equal(result.action, "accept-remote");
    assert.ok(result.warning);
    assert.ok(result.warning!.includes("Simultaneous edit"));
  });
});

describe("resolveChange", () => {
  it("accepts remote when no local content exists", () => {
    const result = resolveChange("team-spec", null, { content: "new", updated_at: 100 }, 0);
    assert.equal(result.action, "accept-remote");
    assert.equal(result.content, "new");
  });

  it("uses merge for knowledge keys", () => {
    const local = "- entry one\n";
    const remote = "- entry one\n- entry two\n";
    const result = resolveChange("knowledge:project", local, { content: remote, updated_at: 100 }, 50);
    assert.equal(result.action, "merged");
    assert.ok(result.content.includes("entry two"));
  });

  it("uses last-write-wins for non-knowledge keys", () => {
    const local = "old content";
    const remote = "new content";
    const result = resolveChange("team-spec", local, { content: remote, updated_at: 200 }, 100);
    assert.equal(result.action, "accept-remote");
    assert.equal(result.content, remote);
  });
});
