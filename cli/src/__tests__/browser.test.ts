import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildInviteUrl, hasSameOrigin } from "../browser.js";

describe("buildInviteUrl", () => {
  it("builds an invite URL from the relay origin", () => {
    assert.equal(
      buildInviteUrl("https://relay.example.com", "trc_inv_abc123"),
      "https://relay.example.com/invite/trc_inv_abc123",
    );
  });

  it("handles trailing slashes and encodes the invite code", () => {
    assert.equal(
      buildInviteUrl("https://relay.example.com/", "trc_inv_a/b"),
      "https://relay.example.com/invite/trc_inv_a%2Fb",
    );
  });
});

describe("hasSameOrigin", () => {
  it("returns true for matching origins", () => {
    assert.equal(
      hasSameOrigin("https://relay.example.com/invite/trc_inv_abc123", "https://relay.example.com"),
      true,
    );
  });

  it("returns false for different origins", () => {
    assert.equal(
      hasSameOrigin("https://evil.example.com/invite/trc_inv_abc123", "https://relay.example.com"),
      false,
    );
  });

  it("returns false for invalid URLs", () => {
    assert.equal(hasSameOrigin("not-a-url", "https://relay.example.com"), false);
  });
});
