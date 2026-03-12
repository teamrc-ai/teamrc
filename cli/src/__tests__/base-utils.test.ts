import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { slugify, sanitizeText, sanitizeMarkerContent, escapeYamlString } from "../adapters/base.js";

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
