/**
 * Shared before/after hooks for E2E tests.
 * Import { before, after } from node:test to use with describe blocks.
 */

import { before } from "node:test";
import { waitForServer, RELAY_URL } from "./helpers.ts";

export { RELAY_URL };

before(async () => {
  await waitForServer(30_000);
});
