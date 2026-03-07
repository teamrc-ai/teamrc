# teamrc Security Audit

**Date:** 2026-03-07
**Scope:** Authentication, authorization, and input validation across CLI and relay

---

## CRITICAL

### 1. No Replay Attack Protection (Timestamp Validation Missing)

**Files:** `teamrc/lib/teamrc_web/plugs/verify_signature.ex`, `cli/src/client.ts`

The `VerifySignature` plug's moduledoc claims that `x-trc-timestamp` is required and checked within a 5-minute window, but **no code actually validates timestamps**. The client never sends an `x-trc-timestamp` header either.

An attacker who intercepts a valid signed request can replay it indefinitely.

**Recommended fix:**
- Client: include `x-trc-timestamp` header with current Unix timestamp
- Client: include the timestamp in the signed message (e.g., sign `timestamp + body`)
- Server: extract the timestamp header, verify it is within 5 minutes of server time, and include it in the verified message

### 2. `joinByInvite` Sends No Signature

**Files:** `cli/src/client.ts:72-84`, `teamrc/lib/teamrc_web/router.ex:29-33`

The `/api/join` route bypasses the `:api` pipeline entirely (uses `:accepts_json` only). The client's `joinByInvite` method sends no `x-trc-signature` header.

While the invite code itself provides some auth, this means:
- Any client can associate an arbitrary `token` with a team by guessing/intercepting an invite code
- The server cannot verify that the token's owner actually controls the corresponding private key
- An attacker could register a victim's token to their team, or register their own token to a victim's team using a leaked invite code

**Recommended fix:** Move `/api/join` behind the `:api` pipeline, require signature verification, and validate that the submitted token matches the signing key.

---

## HIGH

### 3. `pull` Method Signs Empty String Instead of Request Path

**File:** `cli/src/client.ts:120-136`

The `pull` method sends a GET request but calls `signedHeaders("")` which signs an empty string. Meanwhile, the server's `get_sign_message` for GET requests constructs `"GET /path"`. This means either:
- Pull requests always fail auth (if the server verifies correctly), or
- The server falls through to the test fallback and accepts any signature (broken auth)

**Recommended fix:** Use the same pattern as `getTeam` -- sign `"GET #{path}"` and send the signature header.

### 4. No BOLA Check in Controller

**Files:** `teamrc/lib/teamrc_web/controllers/api_controller.ex`, `teamrc/lib/teamrc_web/plugs/verify_signature.ex:43`

The `VerifySignature` plug sets `conn.assigns.verified_token`, but **no controller action checks that `verified_token` matches the `token` parameter in the request**. This means:
- User A can sign a request with their own key
- Submit user B's token in the body/path params
- The plug verifies User A's signature successfully
- The controller operates on User B's team data

For POST requests, the token is extracted from `body_params["token"]`, but the signed body could contain any token. The signature only proves the sender has *a* valid key, not that they own the token in the request.

**Recommended fix:** After signature verification, the plug (or controller) must assert that `conn.assigns.verified_token == params["token"]` for every authenticated endpoint. Better yet, derive the token from the verified public key rather than trusting the request parameter.

### 5. `sync`, `push`, `pull` Routes Don't Include Token in URL

**Files:** `teamrc/lib/teamrc_web/router.ex:36-43`, `teamrc/lib/teamrc_web/plugs/verify_signature.ex:54-59`

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

**File:** `teamrc/lib/teamrc_web/plugs/verify_signature.ex:44-50`

The `else` clause catches all failures with `_ ->` and returns a generic 401. This makes debugging difficult and could mask unexpected errors (e.g., database failures returning as auth errors).

**Recommended fix:** Return specific error messages for different failure modes (missing token, invalid signature, expired timestamp) while being careful not to leak sensitive information.

### 8. `skip_auth` Configuration Could Leak to Production

**File:** `teamrc/lib/teamrc_web/plugs/verify_signature.ex:35`

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

## Code Audit Fixes (2026-03-07)

### 21. Invite codes are multi-use (BY DESIGN)

Invite codes are intentionally multi-use — any number of machines can join a team using the same code before it expires (24h TTL). Security relies on the code's 144-bit entropy (not brute-forceable) and time-bounded expiry, not single-use semantics.

### 33. Sync attribution (MITIGATED)

Synced content (agents, rules, skills, knowledge) is automatically distributed to all team members. This creates a prompt injection surface — a compromised team member could push adversarial instructions via agent definitions.

**Mitigations applied:**
- Every content entry tracks `pushed_by` token for accountability
- `teamrc log` exposes attribution so teams can audit who pushed what
- Daemon defaults to `knowledge` sync mode — only knowledge files sync automatically; agent/rule/skill changes require explicit `teamrc sync`
- `teamrc clone` allows copying a team without joining sync (no ongoing exposure)
- `--no-sync` flag on `join` registers on relay for attribution but disables automatic sync
- Trust boundary is the invite code: sharing an invite code = granting sync access

### 22. HIGH — `create_team_in_db` crash on error (FIXED)

`create_team_in_db` did not handle database error tuples, causing unmatched function clause crashes instead of returning a proper error to the caller.

**Fix applied:** Added pattern matching on `{:error, changeset}` to return structured error responses.

### 23. HIGH — `update_team_in_db` not transactional (FIXED)

Multi-step team updates (members, rules, skills) were not wrapped in a transaction. A failure partway through could leave the team in an inconsistent state.

**Fix applied:** Wrapped the full update sequence in `Repo.transaction/1`.

### 24. MEDIUM — No content cap on sync state (FIXED)

Sync state payloads had no size limit, allowing a single team to store unbounded data on the server and potentially exhaust storage.

**Fix applied:** Enforced a 50MB cap per team on sync state size.

### 25. MEDIUM — No validation on rules/skills count or size (FIXED)

Teams could have unlimited rules and skills of arbitrary size, creating potential for abuse and resource exhaustion.

**Fix applied:** Limited to 50 rules and 50 skills per team, with a 10KB maximum size per individual rule or skill.

### 26. MEDIUM — Member schema missing required validations (FIXED)

The member schema accepted records without enforcing presence of required fields (name, role), allowing incomplete or malformed member entries.

**Fix applied:** Added `validate_required` for all mandatory member fields in the changeset.

### 27. MEDIUM — Clerk JWT issuer validation fail-open (FIXED)

When validating Clerk JWTs, an unrecognized or missing issuer would fall through without rejecting the token, effectively allowing tokens from any issuer.

**Fix applied:** Changed to fail-closed validation that explicitly rejects tokens unless the issuer matches the expected Clerk instance.

### 28. MEDIUM — No prod config validation at boot (FIXED)

Missing or invalid production configuration (database URL, secret keys, Clerk config) would only surface at runtime when the affected code path was hit, rather than failing fast at startup.

**Fix applied:** Added boot-time config validation that checks all required environment variables and raises immediately if any are missing or malformed.

### 29. LOW — Dead code: `pull` route and method, `revoked?/1`, `put_hashes`/`get_changes` (FIXED)

Unused routes and functions were left in the codebase, increasing the attack surface and maintenance burden.

**Fix applied:** Removed all dead code.

### 30. LOW — Duplicate utility functions across adapters (FIXED)

**Fix applied:** Consolidated shared utilities into `base.ts`.

### 31. LOW — N+1 in `resolve_participants` (FIXED)

**Fix applied:** Replaced individual queries with a batch query.

### 32. LOW — ETS table missing `read_concurrency` (FIXED)

**Fix applied:** Added `read_concurrency: true` to ETS table options.

---

## Summary of Required Fixes

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | CRITICAL | No replay protection | Fixed |
| 2 | CRITICAL | joinByInvite unsigned | Fixed |
| 3 | HIGH | pull signs empty string | Fixed |
| 4 | HIGH | No BOLA check | Fixed |
| 5 | HIGH | Token not verified against signing key | Fixed |
| 6 | HIGH | Directory perms | Fixed |
| 7 | MEDIUM | Catch-all error handling | Fixed (specific error reasons) |
| 8 | MEDIUM | skip_auth guard | Fixed (compile-time `Mix.env()` check) |
| 9 | MEDIUM | No rate limiting | Fixed (per-IP + per-token, ETS) |
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
| 21 | — | Invite codes are multi-use | By design |
| 22 | HIGH | `create_team_in_db` crash on error | Fixed |
| 23 | HIGH | `update_team_in_db` not transactional | Fixed |
| 24 | MEDIUM | No content cap on sync state | Fixed (50MB/team) |
| 25 | MEDIUM | No validation on rules/skills count or size | Fixed (50/50, 10KB) |
| 26 | MEDIUM | Member schema missing required validations | Fixed |
| 27 | MEDIUM | Clerk JWT issuer validation fail-open | Fixed (fail-closed) |
| 28 | MEDIUM | No prod config validation at boot | Fixed |
| 29 | LOW | Dead code: `pull` route and method, `revoked?/1`, `put_hashes`/`get_changes` | Fixed (removed) |
| 30 | LOW | Duplicate utility functions across adapters | Fixed (shared in base.ts) |
| 31 | LOW | N+1 in `resolve_participants` | Fixed (batch query) |
| 32 | LOW | ETS table missing `read_concurrency` | Fixed |
| 33 | MEDIUM | Sync content prompt injection surface | Mitigated (attribution, sync modes, clone) |
