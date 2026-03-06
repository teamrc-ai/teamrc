# Auth Implementation Plan

**Design doc:** `docs/plans/2026-03-06-auth-design.md`

## Task 1: DB migrations + schemas (backend-dev)

Create `accounts` and `account_tokens` tables. Add `owner_account_id` to `teams`.

**Files to create:**
- `teamrc/priv/repo/migrations/20260307000001_create_accounts.exs`
- `teamrc/lib/teamrc/schema/account.ex`
- `teamrc/lib/teamrc/schema/account_token.ex`

**Files to modify:**
- `teamrc/lib/teamrc/schema/team.ex` — add `owner_account_id` field
- `teamrc/priv/repo/migrations/20260307000001_create_accounts.exs` — single migration for both tables + teams alter

**Schema details (from design doc):**
```sql
CREATE TABLE accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clerk_user_id VARCHAR(255) NOT NULL UNIQUE,
  email VARCHAR(255),
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE account_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token VARCHAR(255) NOT NULL UNIQUE,
  machine_name VARCHAR(255),
  last_seen_at TIMESTAMP,
  revoked_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX account_tokens_account_id_idx ON account_tokens(account_id);
CREATE INDEX account_tokens_token_idx ON account_tokens(token);

ALTER TABLE teams ADD COLUMN owner_account_id UUID REFERENCES accounts(id);
```

**Tests:** Schema unit tests + migration runs cleanly.

## Task 2: VerifyClerkJWT plug (backend-dev)

New plug that verifies Clerk JWTs for web/dashboard endpoints.

**Files to create:**
- `teamrc/lib/teamrc_web/plugs/verify_clerk_jwt.ex`
- `teamrc/test/teamrc_web/plugs/verify_clerk_jwt_test.exs`

**Requirements:**
- Extract Bearer token from Authorization header
- Verify JWT signature against Clerk JWKS (cached, 5-minute TTL)
- Pin algorithm to RS256 only (use `JOSE.JWT.verify_strict/3`)
- Validate `iss` (Clerk instance domain), `exp` (with 30s skew), `aud`
- Extract `sub` (clerk_user_id) and `email`
- Assign `:clerk_user_id` and `:clerk_email` to conn
- Config: `CLERK_JWKS_URL`, `CLERK_ISSUER`, `CLERK_AUDIENCE` env vars

**Dependencies:** `jose` hex package

## Task 3: Device auth flow — ephemeral storage + endpoints (backend-dev)

Implement the device authorization flow for `teamrc login`.

**Files to create:**
- `teamrc/lib/teamrc/device_auth.ex` — GenServer for ephemeral device requests
- `teamrc/lib/teamrc_web/controllers/auth_controller.ex` — device auth API endpoints
- `teamrc/test/teamrc/device_auth_test.exs`
- `teamrc/test/teamrc_web/controllers/auth_controller_test.exs`

**Endpoints:**
- `POST /api/auth/device` — initiate device auth (ed25519 signed)
- `GET /api/auth/device/:device_code` — poll status (ed25519 signed, bound to originating token)

**GenServer state:**
```elixir
%DeviceRequest{
  device_code: "abc123...",      # 32-byte hex
  user_code: "ABCD-1234",       # 8-char human-readable
  token: "trc_ak_...",           # originating machine token
  status: :pending | :confirmed,
  clerk_user_id: nil,
  expires_at: ~U[...],
  inserted_at: ~U[...],
  failed_attempts: 0
}
```

**Requirements:**
- Device code: random 32-byte hex
- User code: 8-char from restricted alphabet (uppercase + digits, no ambiguous O/0/I/1)
- Expires after 15 minutes
- CLI polls every 5 seconds
- Rate limit: 3 active device requests per token
- Global cap: 10,000 active requests
- Per-code limit: 5 failed attempts → code invalidated
- Periodic sweep of expired requests (every minute)
- Polling endpoint bound to originating token

## Task 4: Web verification + account linking (backend-dev + frontend-dev)

The browser side of device auth: user signs in with Clerk, enters user_code, links machine.

**Files to create/modify:**
- `teamrc/lib/teamrc_web/live/auth_verify_live.ex` — LiveView page
- `teamrc/lib/teamrc_web/templates/auth_verify_live.html.heex` (or inline)
- `teamrc/lib/teamrc_web/router.ex` — add route

**Flow:**
1. User visits `/auth/verify` (optionally with `?code=ABCD-1234`)
2. If not signed in with Clerk, redirect to Clerk sign-in, then back
3. User enters/confirms the user_code
4. Consent screen: "Link machine to your account?"
5. Server: find device request by user_code, verify not expired, create/find account, create account_token, set status to confirmed

**Requirements:**
- CSRF protection via LiveView websocket
- Consent screen showing what will be linked
- Validate machine name (max 255 chars, strip dangerous chars)
- Pre-fill code from URL parameter

## Task 5: Account management API endpoints (backend-dev)

Dashboard data endpoints for the web UI.

**Files to create:**
- `teamrc/lib/teamrc_web/controllers/account_controller.ex`
- `teamrc/test/teamrc_web/controllers/account_controller_test.exs`

**Endpoints:**
- `GET /api/account` — account info + machines (Clerk JWT auth)
- `GET /api/account/teams` — teams with participants (Clerk JWT auth)
- `DELETE /api/account/machines/:token` — revoke machine (Clerk JWT auth)
- `POST /api/account/reassociate` — copy teams to new machine (Clerk JWT + ed25519)

**Requirements:**
- Token must belong to caller's account for revocation
- Reassociation: copies all token_teams from account's non-revoked tokens to new_token
- Revocation: set revoked_at, delete token_teams, message Teams GenServer
- Participants resolved via: team → token_teams → account_tokens → accounts
- Truncate tokens in response (show first 12 chars)

## Task 6: CLI `teamrc login` command (backend-dev)

Device authorization flow from the CLI side.

**Files to modify:**
- `cli/src/index.ts` — add `login` command
- `cli/src/client.ts` — add device auth methods

**Files to create:**
- `cli/src/__tests__/login.test.ts`

**Flow:**
1. Load or generate keypair
2. `POST /api/auth/device` with signed request
3. Open browser to verification URL with user_code
4. Poll `GET /api/auth/device/:device_code` every 5 seconds
5. On confirmation: save account info to `~/.teamrc/config.json`
6. Show: email, machine count, team count

**Config changes:**
- Add `account?: { email: string, clerkUserId: string }` to config
- Add `machineName?: string` to config
- Auto-detect hostname via `os.hostname()`, allow `--name` override

## Task 7: Inline account linking in join/init (backend-dev)

After `teamrc join` or `teamrc init`, prompt to link account.

**Files to modify:**
- `cli/src/index.ts` — add prompt after join/init commands

**Flow:**
```
Link your account for recovery and dashboard access?
[Y/n]: y

Opening browser...
Enter code: ABCD-1234
Waiting for confirmation...

Signed in as ben@example.com
Machine "Bens-MacBook-Pro" linked.
```

## Task 8: Dashboard LiveView page (frontend-dev)

Web dashboard showing machines and teams.

**Files to create:**
- `teamrc/lib/teamrc_web/live/dashboard_live.ex`
- Route in router.ex

**Sections:**
- Your Machines: name, token (truncated), last_seen_at, [Revoke] button
- Your Teams: name, agent_count, rule_count
- Team detail: participants (email or "anonymous participant")

**Requirements:**
- Clerk session required
- Real-time updates via LiveView
- Revocation confirmation dialog
- Privacy: only show caller's machines, never other participants' machines

## Task 9: Security hardening (backend-dev)

**Files to modify:**
- `teamrc/lib/teamrc_web/plugs/verify_signature.ex` — remove `:dev` from `skip_auth_allowed`

**Additions:**
- Email notification on new machine linking (via Clerk webhooks or simple SMTP)
- Email notification on reassociation
- Validate machine names (strip/reject dangerous characters)

## Task 10: Tests (qa-engineer)

Comprehensive test suite for the entire auth feature.

**Test areas:**
- Device auth flow end-to-end
- Account creation and token linking
- Reassociation (all teams copied)
- Revocation (token_teams deleted, GenServer notified)
- JWT verification (valid, expired, wrong algorithm, wrong issuer)
- Rate limiting (per-token, per-code, global cap)
- Privacy (can't see other accounts' machines)
- CLI login flow (mocked endpoints)
