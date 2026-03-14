import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { parseKnowledge, pruneKnowledge } from "../team-yaml.js";

describe("parseKnowledge", () => {
  it("returns empty preamble and no sections for empty string", () => {
    const result = parseKnowledge("");
    assert.equal(result.preamble, "");
    assert.deepEqual(result.sections, []);
  });

  it("returns empty preamble and no sections for undefined-ish input", () => {
    const result = parseKnowledge(undefined as unknown as string);
    assert.equal(result.preamble, "");
    assert.deepEqual(result.sections, []);
  });

  it("parses preamble-only content (no ## headings)", () => {
    const content = "# Team Knowledge\n\nShared findings.\n\nTest commands here.\n";
    const result = parseKnowledge(content);
    assert.equal(result.preamble, content);
    assert.deepEqual(result.sections, []);
  });

  it("parses content with a single section", () => {
    const content =
      "# Knowledge\n\n## Database indexing\nFound index issue.\n";
    const result = parseKnowledge(content);
    assert.equal(result.preamble, "# Knowledge\n\n");
    assert.equal(result.sections.length, 1);
    assert.equal(result.sections[0].heading, "Database indexing");
    assert.equal(result.sections[0].body, "## Database indexing\nFound index issue.\n");
  });

  it("parses multiple sections with correct order", () => {
    const content = [
      "# Knowledge\n",
      "\n",
      "## First topic\n",
      "First body line 1\n",
      "First body line 2\n",
      "\n",
      "## Second topic\n",
      "Second body\n",
      "\n",
      "## Third topic\n",
      "Third body\n",
    ].join("");

    const result = parseKnowledge(content);
    assert.equal(result.preamble, "# Knowledge\n\n");
    assert.equal(result.sections.length, 3);

    assert.equal(result.sections[0].heading, "First topic");
    assert.equal(result.sections[0].body, "## First topic\nFirst body line 1\nFirst body line 2\n\n");

    assert.equal(result.sections[1].heading, "Second topic");
    assert.equal(result.sections[1].body, "## Second topic\nSecond body\n\n");

    assert.equal(result.sections[2].heading, "Third topic");
    assert.equal(result.sections[2].body, "## Third topic\nThird body\n");
  });

  it("handles sections with no blank line between them", () => {
    const content =
      "## Section A\nLine A\n## Section B\nLine B\n";
    const result = parseKnowledge(content);
    assert.equal(result.preamble, "");
    assert.equal(result.sections.length, 2);
    assert.equal(result.sections[0].heading, "Section A");
    assert.equal(result.sections[0].body, "## Section A\nLine A\n");
    assert.equal(result.sections[1].heading, "Section B");
    assert.equal(result.sections[1].body, "## Section B\nLine B\n");
  });

  it("truncates preamble over 10KB at a line boundary", () => {
    // Build a preamble that exceeds 10KB (10240 bytes)
    const line = "A".repeat(99) + "\n"; // 100 bytes per line
    const lineCount = 110; // 11,000 bytes > 10,240
    const bigPreamble = line.repeat(lineCount);
    const content = bigPreamble + "## After preamble\nBody\n";

    const result = parseKnowledge(content);

    // Preamble should be truncated at a line boundary
    const preambleBytes = Buffer.byteLength(result.preamble, "utf8");
    assert.ok(preambleBytes <= 10240, `Preamble ${preambleBytes} bytes exceeds 10KB`);
    assert.ok(preambleBytes > 0, "Preamble should not be empty");
    // The preamble should end with a newline (line boundary truncation)
    assert.ok(result.preamble.endsWith("\n"), "Truncated preamble should end with newline");

    // Sections should still parse correctly
    assert.equal(result.sections.length, 1);
    assert.equal(result.sections[0].heading, "After preamble");
  });

  it("handles content starting with a section (no preamble)", () => {
    const content = "## First\nBody\n";
    const result = parseKnowledge(content);
    assert.equal(result.preamble, "");
    assert.equal(result.sections.length, 1);
    assert.equal(result.sections[0].heading, "First");
  });

  it("does not split on ### or # headings", () => {
    const content = "# Title\n### Not a section split\n## Real section\nBody\n";
    const result = parseKnowledge(content);
    assert.equal(result.preamble, "# Title\n### Not a section split\n");
    assert.equal(result.sections.length, 1);
    assert.equal(result.sections[0].heading, "Real section");
  });

  it("reassembles correctly: preamble + sections = original content", () => {
    const content =
      "# Knowledge\n\nPreamble line.\n\n## Section 1\nBody 1\n\n## Section 2\nBody 2\n";
    const result = parseKnowledge(content);
    const reassembled = result.preamble + result.sections.map((s) => s.body).join("");
    assert.equal(reassembled, content);
  });
});

describe("pruneKnowledge", () => {
  it("returns empty string for empty content", () => {
    assert.equal(pruneKnowledge(""), "");
  });

  it("returns content unchanged when under limit", () => {
    const content = "# Knowledge\n\n## Topic\nSmall body.\n";
    assert.equal(pruneKnowledge(content, 100_000), content);
  });

  it("returns content unchanged when exactly at limit", () => {
    const content = "A".repeat(500);
    assert.equal(pruneKnowledge(content, 500), content);
  });

  it("drops oldest sections first when over limit", () => {
    const preamble = "# Knowledge\n\n";
    const section1 = "## Oldest\n" + "x".repeat(200) + "\n\n";
    const section2 = "## Middle\n" + "y".repeat(200) + "\n\n";
    const section3 = "## Newest\n" + "z".repeat(200) + "\n\n";
    const content = preamble + section1 + section2 + section3;

    // Set max to be smaller than total but big enough for preamble + 2 sections
    const totalBytes = Buffer.byteLength(content, "utf8");
    const maxBytes = totalBytes - 10; // just over the limit

    const result = pruneKnowledge(content, maxBytes);

    // Should have dropped the oldest section
    assert.ok(!result.includes("## Oldest"), "Oldest section should be dropped");
    assert.ok(result.includes("## Newest"), "Newest section should be preserved");
    assert.ok(result.startsWith("# Knowledge\n\n"), "Preamble should be preserved");
  });

  it("preserves preamble even when all sections are dropped", () => {
    const preamble = "# Knowledge\n\nImportant info.\n\n";
    const section1 = "## Big section\n" + "x".repeat(5000) + "\n";
    const content = preamble + section1;

    // Set max so only preamble fits within 80%
    const preambleBytes = Buffer.byteLength(preamble, "utf8");
    const maxBytes = preambleBytes + 10; // preamble fits, section does not

    const result = pruneKnowledge(content, maxBytes);
    assert.equal(result, preamble, "Only preamble should remain");
  });

  it("prunes result to 80% of maxBytes", () => {
    const preamble = "# K\n";
    // Create many sections to build up size
    const sections: string[] = [];
    for (let i = 0; i < 50; i++) {
      sections.push(`## Section ${i}\n${"data".repeat(50)}\n\n`);
    }
    const content = preamble + sections.join("");
    const maxBytes = 5000;

    const result = pruneKnowledge(content, maxBytes);
    const resultBytes = Buffer.byteLength(result, "utf8");

    assert.ok(resultBytes <= maxBytes * 0.8, `Result ${resultBytes} bytes should be <= ${maxBytes * 0.8}`);
    assert.ok(result.startsWith("# K\n"), "Preamble preserved");
  });

  it("handles content with preamble only (no sections) over limit", () => {
    // Even if preamble is over the limit, pruneKnowledge preserves it
    // because preamble is never dropped
    const content = "# Knowledge\n" + "line\n".repeat(100);
    const maxBytes = 50;

    const result = pruneKnowledge(content, maxBytes);
    // Preamble is preserved (no sections to drop)
    assert.equal(result, content, "Preamble-only content is preserved even if over limit");
  });

  it("uses UTF-8 byte length for accurate sizing", () => {
    const preamble = "# K\n";
    // Unicode characters: each emoji is 4 bytes in UTF-8
    const section1 = "## Old\n" + "\u{1F600}".repeat(100) + "\n\n"; // 400 bytes of emoji
    const section2 = "## New\n" + "a".repeat(100) + "\n\n"; // 100 bytes ASCII
    const content = preamble + section1 + section2;

    const totalBytes = Buffer.byteLength(content, "utf8");
    // Set max so that dropping section1 makes it fit
    const withoutSection1 = Buffer.byteLength(preamble + section2, "utf8");
    const maxBytes = Math.floor(withoutSection1 / 0.8) + 1;

    const result = pruneKnowledge(content, maxBytes);
    assert.ok(!result.includes("## Old"), "Section with emoji should be dropped");
    assert.ok(result.includes("## New"), "ASCII section should remain");
  });
});
