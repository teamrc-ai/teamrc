# teamrc Security Audit

**Date:** 2026-03-05
**Scope:** Authentication, authorization, and input validation across CLI and relay

---

## CRITICAL

### 1. No Replay Attack Protection (Timestamp Validation Missing)

**Files:** `relay/lib/teamrc_web/plugs/verify_signature.ex`, `cli/src/relay-client.ts`

The `VerifySignature` plug's moduledoc claims that `x-tb-timestamp` is required and checked within a 5-minute window, but **no code actually validates timestamps**. The client never sends an `x-tb-timestamp` header either.

An attacker who intercepts a valid signed request can replay it indefinitely.

**Recommended fix:**
- Client: include `x-tb-timestamp` header with current Unix timestamp
- Client: include the timestamp in the signed message (e.g., sign `timestamp + body`)
- Server: extract the timestamp header, verify it is within 5 minutes of server time, and include it in the verified message

### 2. `joinByInvite` Sends No Signature

**Files:** `cli/src/relay-client.ts:72-84`, `relay/lib/relay_web/router.ex:29-33`

The `/api/join` route bypasses the `:api` pipeline entirely (uses `:accepts_json` only). The client's `joinByInvite` method sends no `x-tb-signature` header.

While the invite code itself provides some auth, this means:
- Any client can associate an arbitrary `token` with a team by guessing/intercepting an invite code
- The server cannot verify that the token's owner actually controls the corresponding private key
- An attacker could register a victim's token to their team, or register their own token to a victim's team using a leaked invite code

**Recommended fix:** Move `/api/join` behind the `:api` pipeline, require signature verification, and validate that the submitted token matches the signing key.

---

## HIGH

### 3. `pull` Method Signs Empty String Instead of Request Path

**File:** `cli/src/relay-client.ts:120-136`

The `pull` method sends a GET request but calls `signedHeaders("")` which signs an empty string. Meanwhile, the server's `get_sign_message` for GET requests constructs `"GET /path"`. This means either:
- Pull requests always fail auth (if the server verifies correctly), or
- The server falls through to the test fallback and accepts any signature (broken auth)

**Recommended fix:** Use the same pattern as `getTeam` -- sign `"GET #{path}"` and send the signature header.

### 4. No BOLA Check in Controller

**Files:** `relay/lib/teamrc_web/controllers/api_controller.ex`, `relay/lib/teamrc_web/plugs/verify_signature.ex:43`

The `VerifySignature` plug sets `conn.assigns.verified_token`, but **no controller action checks that `verified_token` matches the `token` parameter in the request**. This means:
- User A can sign a request with their own key
- Submit user B's token in the body/path params
- The plug verifies User A's signature successfully
- The controller operates on User B's team data

For POST requests, the token is extracted from `body_params["token"]`, but the signed body could contain any token. The signature only proves the sender has *a* valid key, not that they own the token in the request.

**Recommended fix:** After signature verification, the plug (or controller) must assert that `conn.assigns.verified_token == params["token"]` for every authenticated endpoint. Better yet, derive the token from the verified public key rather than trusting the request parameter.

### 5. `sync`, `push`, `pull` Routes Don't Include Token in URL

**Files:** `relay/lib/relay_web/router.ex:36-43`, `relay/lib/teamrc_web/plugs/verify_signature.ex:54-59`

Routes like `post "/sync"`, `post "/push"`, `post "/pull"` don't have `:token` in the path. The `extract_token` plug tries `body_params["token"]` first, then `path_params["token"]`.

For POST, the token comes from the body, which is also the signed message. This creates a circular dependency: the token used to look up the public key is embedded in the message that was signed. An attacker could craft a body with their own token and sign it validly.

This is partially mitigated by the token-to-key derivation (the token *is* the public key), but combined with finding #4, it enables cross-account access.

**Recommended fix:** Ensure that the public key extracted from the token matches the public key that verified the signature. Add this check to the plug.

### 6. Directory Permissions Not Set on `~/.teamrc`

**File:** `cli/src/auth.ts:54-57`

The key file is written with mode `0o600` (good), but the directory `~/.teamrc` is created with default permissions (typically `0o755`), meaning other users on the system can list directory contents and see the key filename.

**Recommended fix:** Create the directory with `0o700`:
```typescript
fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
```

---

## MEDIUM

### 7. Catch-All Error Handling Hides Auth Failures

**File:** `relay/lib/teamrc_web/plugs/verify_signature.ex:44-50`

The `else` clause catches all failures with `_ ->` and returns a generic 401. This makes debugging difficult and could mask unexpected errors (e.g., database failures returning as auth errors).

**Recommended fix:** Return specific error messages for different failure modes (missing token, invalid signature, expired timestamp) while being careful not to leak sensitive information.

### 8. `skip_auth` Configuration Could Leak to Production

**File:** `relay/lib/teamrc_web/plugs/verify_signature.ex:35`

`Application.get_env(:relay, :skip_auth, false)` reads at runtime. If this config accidentally gets set in production, all auth is bypassed. There is no compile-time guard.

**Recommended fix:** Only allow `skip_auth` in `:test` and `:dev` environments:
```elixir
if Application.get_env(:relay, :skip_auth, false) and Mix.env() in [:test, :dev] do
```
Note: `Mix.env()` is not available at runtime in releases. Use a compile-time module attribute instead.

### 9. No Rate Limiting on Auth Endpoints

No rate limiting is applied to the API routes. An attacker could brute-force invite codes or flood the sync endpoint.

**Recommended fix:** Add rate limiting per IP/token using a plug like `PlugAttack` or a custom token bucket.

### 10. WebSocket Auth Recommendation

When Phoenix Channels are added, the WebSocket connection must be authenticated at connect time:
- Client sends the token and a signed timestamp in the `connect` params
- The `UserSocket.connect/3` callback verifies the signature before allowing the connection
- Channel joins should verify the token is authorized for the requested team
- Do NOT rely on per-message signing for WebSocket (too expensive); authenticate once at connect

---

## LOW

### 11. Token Format Is Transparent

The token format `trc_ak_<base64url(pubkey)>` directly exposes the public key. While public keys are meant to be public, this makes it trivial for anyone who sees a token to verify signatures without needing server involvement.

This is not a vulnerability per se, but worth noting: tokens should be treated as semi-sensitive (they identify the user and enable targeted attacks if combined with other bugs).

### 12. No Key Rotation Mechanism

There is no way to rotate keys. If a private key is compromised, the user must generate a new keypair, get a new token, and re-join all teams.

**Recommended fix (future):** Add a key rotation endpoint where the old key signs a request containing the new public key.

### 13. GenServer State Not Persisted

Team-to-token mappings in `Teamrc.Teams` GenServer are in-memory only. A server restart loses all token-team associations (though Postgres teams persist). This is an availability concern, not directly a security issue.

---

---

## YAML Source-of-Truth Security (2026-03-06)

### 14. CRITICAL — Missing validateAgentName in writeTeam() (FIXED)

**Files:** `cli/src/adapters/claude-code.ts:77`, `cli/src/adapters/openclaw.ts:105`

Agent names from YAML were passed to adapters without validation. A malicious `agent-team.yaml` with path traversal names could write files outside the agents directory.

**Fix applied:** Added `validateAgentName(member.name)` in both adapters' `writeTeam()` methods, and at YAML parse time in `readTeamYaml()`.

### 15. HIGH — YAML frontmatter injection via role/teamName (FIXED)

**File:** `cli/src/adapters/claude-code.ts:440-453`

Member roles were interpolated directly into YAML double-quoted strings in agent file frontmatter. A role containing `"` could break out and inject arbitrary YAML fields.

**Fix applied:** Added `escapeYamlString()` helper that escapes `\`, `"`, and newlines. Applied to role and team name in frontmatter.

### 16. HIGH — No YAML file size limit (FIXED)

**File:** `cli/src/team-yaml.ts:5-6`

No size check before `fs.readFileSync()` and `YAML.parse()`. A multi-GB YAML file or YAML bomb could cause memory exhaustion.

**Fix applied:** Added `MAX_YAML_SIZE = 256KB` check before reading, and `MAX_MEMBERS = 100` limit on the members array.

### 17. MEDIUM — CLAUDE.md injection via team name (FIXED)

**File:** `cli/src/adapters/claude-code.ts:471-485`

Team names with newlines could inject arbitrary content into CLAUDE.md, a high-trust file.

**Fix applied:** Added `sanitizeTeamName()` and `sanitizeText()` that strip newlines. Applied to team name and member names/roles in all template outputs.

### 18. MEDIUM — Daemon race conditions (FIXED)

**File:** `cli/src/daemon.ts:60-90`

Multiple file changes could trigger overlapping `pushChanges()` calls via `void` fire-and-forget.

**Fix applied:** Added sync mutex (`syncing`/`syncQueued` flags) so only one sync runs at a time, with subsequent triggers queued.

### 19. MEDIUM — No team name validation (FIXED)

**File:** `cli/src/team-yaml.ts:8-12`, `cli/src/index.ts:519,548`

Team names from YAML and relay were not validated. Malicious names could contain control characters or be excessively long.

**Fix applied:** Added `validateTeamName()` regex (`^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$`). Applied at YAML parse time and in export/pull commands.

### 20. MEDIUM — Prompt injection via soul content (BY DESIGN)

Agent `soul` fields are intentionally user-controlled persona text. A malicious `agent-team.yaml` committed to a shared repo could inject adversarial instructions.

**Mitigation:** `agent-team.yaml` should be treated as a trusted configuration file (like `.env`). Review YAML changes in PRs just as you would review code changes.

---

## Summary of Required Fixes

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | CRITICAL | No replay protection | Fixed |
| 2 | CRITICAL | joinByInvite unsigned | Fixed |
| 3 | HIGH | pull signs empty string | Fixed |
| 4 | HIGH | No BOLA check | Fixed |
| 5 | HIGH | Token not verified against signing key | Fixed (via #4 fix) |
| 6 | HIGH | Directory perms | Fixed |
| 7 | MEDIUM | Catch-all error handling | Noted |
| 8 | MEDIUM | skip_auth guard | Noted |
| 9 | MEDIUM | No rate limiting | Noted |
| 10 | MEDIUM | WebSocket auth design | Noted |
| 11 | LOW | Transparent token format | Noted |
| 12 | LOW | No key rotation | Noted |
| 13 | LOW | GenServer state loss | Noted |
| 14 | CRITICAL | Missing validateAgentName in writeTeam | Fixed |
| 15 | HIGH | YAML frontmatter injection | Fixed |
| 16 | HIGH | No YAML file size limit | Fixed |
| 17 | MEDIUM | CLAUDE.md injection via team name | Fixed |
| 18 | MEDIUM | Daemon race conditions | Fixed |
| 19 | MEDIUM | No team name validation | Fixed |
| 20 | MEDIUM | Prompt injection via soul | By design |
