import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { logKnowledgeSize, KNOWLEDGE_CAP } from "../knowledge-log.js";

function createMockLog() {
  const calls: { level: string; message: string }[] = [];
  return {
    calls,
    info: (msg: string) => calls.push({ level: "info", message: msg }),
    warn: (msg: string) => calls.push({ level: "warn", message: msg }),
    error: (msg: string) => calls.push({ level: "error", message: msg }),
    step: (msg: string) => calls.push({ level: "step", message: msg }),
    success: (msg: string) => calls.push({ level: "success", message: msg }),
    message: (msg: string) => calls.push({ level: "message", message: msg }),
  };
}

describe("KNOWLEDGE_CAP", () => {
  it("is 100,000 bytes", () => {
    assert.equal(KNOWLEDGE_CAP, 100_000);
  });
});

describe("logKnowledgeSize", () => {
  it("logs nothing when size is below 70% of cap", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 50_000); // 50%
    assert.equal(log.calls.length, 0);
  });

  it("logs nothing at exactly 70% of cap", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 70_000); // exactly 70%
    assert.equal(log.calls.length, 0);
  });

  it("logs info when size is between 70% and 90% of cap", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 75_000); // 75%
    assert.equal(log.calls.length, 1);
    assert.equal(log.calls[0].level, "info");
    assert.match(log.calls[0].message, /73KB \/ 98KB/);
  });

  it("logs info at just above 70%", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 70_001); // just over 70%
    assert.equal(log.calls.length, 1);
    assert.equal(log.calls[0].level, "info");
  });

  it("logs warn when size exceeds 90% of cap", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 95_000); // 95%
    assert.equal(log.calls.length, 1);
    assert.equal(log.calls[0].level, "warn");
    assert.match(log.calls[0].message, /nearly full/);
    assert.match(log.calls[0].message, /93KB \/ 98KB/);
  });

  it("logs warn at just above 90%", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 90_001); // just over 90%
    assert.equal(log.calls.length, 1);
    assert.equal(log.calls[0].level, "warn");
    assert.match(log.calls[0].message, /pruned automatically/);
  });

  it("logs warn at exactly the cap", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 100_000); // 100%
    assert.equal(log.calls.length, 1);
    assert.equal(log.calls[0].level, "warn");
  });

  it("logs nothing for zero bytes", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 0);
    assert.equal(log.calls.length, 0);
  });

  it("logs nothing for small content", () => {
    const log = createMockLog();
    logKnowledgeSize(log as any, 1024); // 1KB
    assert.equal(log.calls.length, 0);
  });
});
