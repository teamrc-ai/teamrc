import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { validateTeamName, validateSkillId, mergeKnowledge } from "../team-yaml.js";
import { validateAgentName } from "../adapters/base.js";

describe("validateTeamName", () => {
  it("accepts simple alphanumeric name", () => {
    assert.doesNotThrow(() => validateTeamName("my-team"));
  });

  it("accepts name with spaces", () => {
    assert.doesNotThrow(() => validateTeamName("My Team Name"));
  });

  it("accepts name with underscores", () => {
    assert.doesNotThrow(() => validateTeamName("my_team"));
  });

  it("accepts name with hyphens", () => {
    assert.doesNotThrow(() => validateTeamName("my-team-2"));
  });

  it("accepts single character name", () => {
    assert.doesNotThrow(() => validateTeamName("a"));
  });

  it("accepts exactly 64 character name (boundary)", () => {
    const name = "a" + "b".repeat(63);
    assert.equal(name.length, 64);
    assert.doesNotThrow(() => validateTeamName(name));
  });

  it("rejects 65 character name", () => {
    const name = "a" + "b".repeat(64);
    assert.equal(name.length, 65);
    assert.throws(() => validateTeamName(name), /Invalid team name/);
  });

  it("rejects empty string", () => {
    assert.throws(() => validateTeamName(""), /Invalid team name/);
  });

  it("rejects name starting with space", () => {
    assert.throws(() => validateTeamName(" my-team"), /Invalid team name/);
  });

  it("rejects name starting with hyphen", () => {
    assert.throws(() => validateTeamName("-my-team"), /Invalid team name/);
  });

  it("rejects name starting with underscore", () => {
    assert.throws(() => validateTeamName("_my-team"), /Invalid team name/);
  });

  it("rejects name with special characters", () => {
    assert.throws(() => validateTeamName("my@team"), /Invalid team name/);
    assert.throws(() => validateTeamName("my!team"), /Invalid team name/);
    assert.throws(() => validateTeamName("team#1"), /Invalid team name/);
  });

  it("rejects name with unicode characters", () => {
    assert.throws(() => validateTeamName("my-te\u00e4m"), /Invalid team name/);
    assert.throws(() => validateTeamName("\u2603 snowman"), /Invalid team name/);
  });

  it("rejects name with newlines", () => {
    assert.throws(() => validateTeamName("my\nteam"), /Invalid team name/);
  });
});

describe("validateAgentName", () => {
  it("accepts simple alphanumeric name", () => {
    assert.doesNotThrow(() => validateAgentName("architect"));
  });

  it("accepts name with hyphens", () => {
    assert.doesNotThrow(() => validateAgentName("code-reviewer"));
  });

  it("accepts name with underscores", () => {
    assert.doesNotThrow(() => validateAgentName("code_reviewer"));
  });

  it("accepts single character name", () => {
    assert.doesNotThrow(() => validateAgentName("a"));
  });

  it("accepts exactly 64 character name (boundary)", () => {
    const name = "a" + "b".repeat(63);
    assert.equal(name.length, 64);
    assert.doesNotThrow(() => validateAgentName(name));
  });

  it("rejects 65 character name", () => {
    const name = "a" + "b".repeat(64);
    assert.equal(name.length, 65);
    assert.throws(() => validateAgentName(name), /Invalid agent name/);
  });

  it("rejects empty string", () => {
    assert.throws(() => validateAgentName(""), /Invalid agent name/);
  });

  it("rejects name starting with hyphen", () => {
    assert.throws(() => validateAgentName("-agent"), /Invalid agent name/);
  });

  it("rejects name starting with underscore", () => {
    assert.throws(() => validateAgentName("_agent"), /Invalid agent name/);
  });

  it("rejects name with spaces (unlike team names)", () => {
    assert.throws(() => validateAgentName("my agent"), /Invalid agent name/);
  });

  it("rejects name with dots", () => {
    assert.throws(() => validateAgentName("my.agent"), /Invalid agent name/);
  });

  it("rejects name with slashes", () => {
    assert.throws(() => validateAgentName("my/agent"), /Invalid agent name/);
    assert.throws(() => validateAgentName("../escape"), /Invalid agent name/);
  });

  it("rejects name with unicode characters", () => {
    assert.throws(() => validateAgentName("\u00fcber-agent"), /Invalid agent name/);
  });
});

describe("validateSkillId", () => {
  it("accepts valid alphanumeric IDs", () => {
    assert.doesNotThrow(() => validateSkillId("skill_search"));
    assert.doesNotThrow(() => validateSkillId("deploy"));
    assert.doesNotThrow(() => validateSkillId("code-review"));
  });

  it("accepts single character ID", () => {
    assert.doesNotThrow(() => validateSkillId("s"));
  });

  it("accepts exactly 64 character ID (boundary)", () => {
    const id = "a" + "b".repeat(63);
    assert.equal(id.length, 64);
    assert.doesNotThrow(() => validateSkillId(id));
  });

  it("rejects 65 character ID", () => {
    const id = "a" + "b".repeat(64);
    assert.equal(id.length, 65);
    assert.throws(() => validateSkillId(id), /Invalid skill ID/);
  });

  it("rejects empty string", () => {
    assert.throws(() => validateSkillId(""), /Invalid skill ID/);
  });

  it("rejects ID with slashes (path traversal)", () => {
    assert.throws(() => validateSkillId("../traversal"), /Invalid skill ID/);
    assert.throws(() => validateSkillId("path/skill"), /Invalid skill ID/);
  });

  it("rejects ID with dots", () => {
    assert.throws(() => validateSkillId("skill.name"), /Invalid skill ID/);
  });

  it("rejects ID with newlines", () => {
    assert.throws(() => validateSkillId("skill\ninjection"), /Invalid skill ID/);
  });

  it("rejects ID starting with hyphen", () => {
    assert.throws(() => validateSkillId("-skill"), /Invalid skill ID/);
  });

  it("rejects ID starting with underscore", () => {
    assert.throws(() => validateSkillId("_skill"), /Invalid skill ID/);
  });

  it("rejects ID with spaces", () => {
    assert.throws(() => validateSkillId("skill name"), /Invalid skill ID/);
  });
});

describe("mergeKnowledge", () => {
  it("both empty returns empty", () => {
    const result = mergeKnowledge("", "");
    assert.equal(result, "");
  });

  it("local empty returns remote", () => {
    const result = mergeKnowledge("remote line", "");
    assert.equal(result, "remote line");
  });

  it("remote empty returns local", () => {
    const result = mergeKnowledge("", "local line");
    assert.equal(result, "local line");
  });

  it("local adds new lines appended after remote", () => {
    const remote = "existing line";
    const local = "existing line\nnew local insight";
    const result = mergeKnowledge(remote, local);
    assert.ok(result.includes("existing line"));
    assert.ok(result.includes("new local insight"));
  });

  it("deduplicates existing lines", () => {
    const remote = "line one\nline two";
    const local = "line one\nline two\nline three";
    const result = mergeKnowledge(remote, local);

    const matches = result.match(/line one/g);
    assert.equal(matches?.length, 1);
    assert.ok(result.includes("line three"));
  });

  it("handles whitespace-only differences (trims for comparison)", () => {
    const remote = "line with spaces";
    const local = "  line with spaces  ";
    const result = mergeKnowledge(remote, local);

    const matches = result.match(/line with spaces/g);
    assert.equal(matches?.length, 1);
  });

  it("preserves remote content when no new local lines", () => {
    const remote = "line a\nline b\nline c";
    const local = "line b\nline a";
    const result = mergeKnowledge(remote, local);
    assert.equal(result, remote);
  });

  it("remote is base, local lines appended at end", () => {
    const remote = "line a\nline b";
    const local = "line c\nline d";
    const result = mergeKnowledge(remote, local);
    assert.ok(result.startsWith("line a\nline b"));
    assert.ok(result.includes("line c"));
    assert.ok(result.includes("line d"));
  });

  it("ignores blank lines in local for dedup", () => {
    const remote = "line one";
    const local = "\n\nline one\n\n";
    const result = mergeKnowledge(remote, local);
    assert.equal(result, remote);
  });
});
