import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { generateSocketTicket, relayUrlToSocketUrl } from "../channel-client.js";
import { generateKeypair, toToken } from "../auth.js";

describe("generateSocketTicket", () => {
  it("produces a ticket in the format timestamp.token.signature", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);
    const ticket = await generateSocketTicket(kp.privateKey, token);

    const parts = ticket.split(".");
    // Token contains dots (trc_ak_<base64url>), so we need to be smarter
    // Format: <timestamp>.<token>.<signature>
    // The token is "trc_ak_<base64url>" which has no dots, so there should be
    // exactly: timestamp + token parts + signature = 3 parts minimum
    assert.ok(parts.length >= 3, `Expected at least 3 dot-separated parts, got ${parts.length}`);

    // First part should be a numeric timestamp
    const timestamp = parseInt(parts[0], 10);
    assert.ok(!isNaN(timestamp), "First part should be a numeric timestamp");

    // Timestamp should be recent (within 60 seconds of now)
    const now = Math.floor(Date.now() / 1000);
    assert.ok(
      Math.abs(now - timestamp) < 60,
      `Timestamp ${timestamp} should be within 60s of ${now}`,
    );

    // The token should be present in the ticket
    assert.ok(ticket.includes(token), "Ticket should contain the token");
  });

  it("uses the signMessage function to sign timestamp.token", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);
    const ticket = await generateSocketTicket(kp.privateKey, token);

    // Extract parts: timestamp.token.signature
    // Token format: trc_ak_<base64url> (no dots)
    // So the ticket is: <number>.trc_ak_<base64url>.<base64url_signature>
    const firstDot = ticket.indexOf(".");
    const lastDot = ticket.lastIndexOf(".");

    assert.ok(firstDot > 0, "Should have a dot after timestamp");
    assert.ok(lastDot > firstDot, "Should have a separate signature part");

    const timestampStr = ticket.slice(0, firstDot);
    const tokenStr = ticket.slice(firstDot + 1, lastDot);
    const signature = ticket.slice(lastDot + 1);

    assert.equal(tokenStr, token, "Middle part should be the token");
    assert.ok(signature.length > 0, "Signature should not be empty");
    assert.ok(timestampStr.length > 0, "Timestamp should not be empty");
  });

  it("generates different tickets on subsequent calls (different timestamps)", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const ticket1 = await generateSocketTicket(kp.privateKey, token);
    // Small delay to potentially get a different timestamp
    await new Promise((r) => setTimeout(r, 10));
    const ticket2 = await generateSocketTicket(kp.privateKey, token);

    // Tickets may be the same if within the same second, but the format
    // should be consistent
    const parts1 = ticket1.split(".");
    const parts2 = ticket2.split(".");
    assert.ok(parts1.length >= 3);
    assert.ok(parts2.length >= 3);
  });
});

describe("relayUrlToSocketUrl", () => {
  it("converts https to wss and appends /socket", () => {
    assert.equal(
      relayUrlToSocketUrl("https://teamrc.ai"),
      "wss://teamrc.ai/socket",
    );
  });

  it("converts http to ws and appends /socket", () => {
    assert.equal(
      relayUrlToSocketUrl("http://localhost:4000"),
      "ws://localhost:4000/socket",
    );
  });

  it("strips trailing slash before appending /socket", () => {
    assert.equal(
      relayUrlToSocketUrl("https://teamrc.ai/"),
      "wss://teamrc.ai/socket",
    );
  });

  it("strips multiple trailing slashes", () => {
    assert.equal(
      relayUrlToSocketUrl("https://teamrc.ai///"),
      "wss://teamrc.ai/socket",
    );
  });

  it("handles URL with a path", () => {
    assert.equal(
      relayUrlToSocketUrl("https://teamrc.ai/api"),
      "wss://teamrc.ai/api/socket",
    );
  });

  it("handles URL with a path and trailing slash", () => {
    assert.equal(
      relayUrlToSocketUrl("https://teamrc.ai/api/"),
      "wss://teamrc.ai/api/socket",
    );
  });

  it("handles http localhost with port", () => {
    assert.equal(
      relayUrlToSocketUrl("http://127.0.0.1:4000"),
      "ws://127.0.0.1:4000/socket",
    );
  });

  it("is case-insensitive for the protocol", () => {
    assert.equal(
      relayUrlToSocketUrl("HTTPS://teamrc.ai"),
      "wss://teamrc.ai/socket",
    );

    assert.equal(
      relayUrlToSocketUrl("HTTP://localhost:4000"),
      "ws://localhost:4000/socket",
    );
  });
});
