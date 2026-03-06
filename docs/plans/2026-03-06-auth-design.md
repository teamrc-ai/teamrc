# Auth Design: Optional Account Layer with Clerk

**Date:** 2026-03-07
**Status:** Draft

## Problem

TeamBridge uses ed25519 keypairs for machine identity. If a user loses `~/.teambridge/key`, they lose access to all their teams. There's no way to:
- Recover access from a new machine
- See all teams across multiple machines in one place
- Revoke a compromised machine

## Design Principles

1. **Zero signup to use the product.** `teambridge join <invite>` works exactly as today. No Clerk, no email, no account required.
2. **Machine key = primary identity.** Ed25519 keypair remains the authentication mechanism for all API calls. Clerk is additive.
3. **Account = your machines.** A Clerk account groups your machine tokens. It enables recovery, dashboard visibility, and revocation. It does NOT expose your machines to other team participants.
4. **Teams are shared, machines are private.** Teams can have multiple participants (via invite codes). When viewing a team, you see participants (accounts/emails if linked, anonymous otherwise). You never see another participant's machine names or token details.
5. **Linking requires both sides.** Valid ed25519 signature (proves machine ownership) + valid Clerk JWT (proves human identity). Knowing someone's token alone is not enough.
6. **Once per machine, not per terminal.** `teambridge login` links the machine's keypair (stored in `~/.teambridge/key`) to the account. All terminals on that machine share the same key, so login only happens once.

## Visibility Model

### What you see on the dashboard

**Your Machines** (private to your account):
```
Machines
  MacBook-Pro       tb_ak_abc...   Last seen: 2 min ago    [Revoke]
  Linux-Server      tb_ak_def...   Last seen: 1 hour ago   [Revoke]
```

Only you see your machine names and tokens. Other participants never see this.

**Your Teams** (shared view):
```
Teams
  product-team          6 agents, 2 rules
  backend-team          4 agents, 2 rules
```

**Team detail page** (shows participants, not machines):
```
product-team
  Participants:
    ben@example.com        (you, owner)
    alice@example.com
    2 anonymous participants
```

- Linked accounts show email
- Unlinked machines show as "anonymous participant" (they joined via invite but never ran `teambridge login`)
- No one sees another person's machine names, token details, or how many machines they have

### Privacy boundary

| Data | Visible to you | Visible to team participants |
|---|---|---|
| Your machine names | Yes | No |
| Your tokens | Yes (truncated) | No |
| Your email | Yes | Yes (if on same team) |
| Team members/rules/skills | Yes | Yes |
| Other participant's email | Yes | Yes |
| Other participant's machines | No | No |

## Data Model

### New tables

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
```

### Modified tables

```sql
-- Add owner to teams (nullable — unowned until someone links an account)
ALTER TABLE teams ADD COLUMN owner_account_id UUID REFERENCES accounts(id);
```

### Existing tables (otherwise unchanged)

- `token_teams` — maps machine token to team. Still the source of truth for "which teams does this machine have?"
- `teams`, `members`, `invites` — unchanged

### Relationships

```
Account (Clerk user)
  └── AccountToken (machine)
        └── TokenTeam (team membership)
              └── Team
                    └── [other TokenTeams from other participants]
                          └── [other AccountTokens → other Accounts]
```

To resolve "participants in a team": follow token_teams → account_tokens → accounts. Tokens without an account_token entry are "anonymous participants."

## Flows

### 1. Create team on web, join from CLI

```
Browser: https://teambridge.dev

  [Pick template, customize, create]

  product-team created!
  $ npx teambridge join tb_inv_abc123
```

```
$ npx teambridge join tb_inv_abc123

  Joined team: product-team (6 agents)
  Detected platform: claude-code
  Setting up... done.

  Link your account for recovery and dashboard access?
  [Y/n]: y

  Opening browser...
  Enter code: ABCD-1234
  Waiting for confirmation...

  Signed in as ben@example.com
  Machine "Bens-MacBook-Pro" linked.

  Team is syncing. Your agents are ready.
```

### 2. Colleague joins the same team

```
$ npx teambridge join tb_inv_abc123

  Joined team: product-team (6 agents)
  Detected platform: cursor
  Setting up... done.

  Link your account for recovery and dashboard access?
  [Y/n]: n

  Team is syncing. Your agents are ready.
  Tip: Run `teambridge login` anytime to link your account.
```

Alice is now an anonymous participant. Ben's dashboard shows "1 anonymous participant" on the team. Alice's machines are not visible to Ben.

### 3. `teambridge login` (Device Authorization)

Standalone command for linking a machine later, or on a second machine.

```
$ teambridge login

  Open in browser: https://teambridge.dev/auth/verify
  Enter code: ABCD-1234

  Waiting for confirmation... (press Ctrl+C to cancel)

  Signed in as ben@example.com
  Machine "Bens-MacBook-Pro" linked.
  2 teams across 1 machine.
```

**Sequence:**

```
CLI                          Server                      Browser
 |                             |                            |
 |-- POST /api/auth/device --> |                            |
 |   { token: tb_ak_... }     |                            |
 |                             |                            |
 | <-- { device_code,         |                            |
 |       user_code: ABCD-1234,|                            |
 |       verification_url,    |                            |
 |       expires_in: 900,     |                            |
 |       interval: 5 }        |                            |
 |                             |                            |
 |  [opens browser]            |                            |
 |                             |          [user visits /auth/verify]
 |                             |          [signs in with Clerk]
 |                             |          [enters ABCD-1234]
 |                             |                            |
 |                             | <-- POST /auth/verify      |
 |                             |   { user_code, clerk_jwt } |
 |                             |                            |
 |                             |  [links token to account]  |
 |                             |                            |
 |-- GET /api/auth/device/:dc->|                            |
 |                             |                            |
 | <-- { status: "confirmed", |                            |
 |       email, machine_count, |                            |
 |       team_count }          |                            |
```

**Device code details:**
- `device_code`: random 32-byte hex, used by CLI to poll
- `user_code`: human-readable 8-char code (e.g., `ABCD-1234`), entered on web
- Expires after 15 minutes
- CLI polls every 5 seconds
- Rate limited: per-IP AND global per user_code (5 failed attempts → code invalidated)
- Polling endpoint bound to originating token (only the token that initiated can poll)

**Server-side storage (ephemeral):**
```elixir
# In-memory (ETS or GenServer state), not persisted
%DeviceRequest{
  device_code: "abc123...",
  user_code: "ABCD-1234",
  token: "tb_ak_...",           # machine token from CLI
  status: :pending | :confirmed,
  clerk_user_id: nil,           # set on confirmation
  expires_at: ~U[...],
  inserted_at: ~U[...],
  failed_attempts: 0            # global counter, invalidate at 5
}
```

### 4. Recovery (Lost Key)

```
$ teambridge login

  No existing keypair found. Generated new machine key.

  Opening browser...
  Enter code: EFGH-5678
  Waiting for confirmation...

  Signed in as ben@example.com
  Machine "Bens-MacBook-Air" linked.

  Found teams from your other machines:
    product-team
    backend-team

  Reassociate to this machine? [Y/n]: y
  Reassociated 2 teams. Syncing...
```

**How it works:**
1. CLI generates a new keypair (new token)
2. Device auth flow links new token to existing Clerk account
3. Server finds all teams reachable through the account's other tokens
4. CLI asks to reassociate (all-or-nothing, no cherry-picking team_ids)
5. Server creates new `token_teams` entries for the new token
6. Old token remains valid (other machines might still use it)
7. Email notification sent to account owner when a new machine is linked

### 5. Revocation

From the dashboard:

```
Machines
  MacBook-Pro    [Revoke]

Are you sure? This machine will lose access to all teams.
[Revoke Machine]
```

**What happens:**
1. Sets `revoked_at` on `account_tokens`
2. Deletes `token_teams` rows for the revoked token (persisted revocation)
3. Sends message to GenServer to remove token from in-memory `token_teams` map (immediate)
4. Revoked token's ed25519 signatures are still cryptographically valid, but the server rejects them because the token has no team associations

## API Endpoints

### Device Auth (CLI-initiated)

**`POST /api/auth/device`**
- Auth: ed25519 signature (standard VerifySignature plug)
- Body: `{ token: "tb_ak_..." }`
- Response: `{ device_code, user_code, verification_url, expires_in, interval }`
- Rate limit: 3 active device requests per token

**`GET /api/auth/device/:device_code`**
- Auth: ed25519 signature
- Validation: polling token must match originating token
- Response (pending): `{ status: "pending" }`
- Response (confirmed): `{ status: "confirmed", email, machine_count, team_count }`
- Response (expired): `404`

### Web Verification (Clerk-authenticated)

**`POST /auth/verify`** (LiveView websocket — built-in CSRF protection)
- Auth: Clerk session (browser)
- Body: `{ user_code: "ABCD-1234" }`
- Action: Links the machine token from the device request to the Clerk account
- Response: success page

### Account Management (Clerk-authenticated)

**`GET /api/account`**
- Auth: Clerk JWT
- Response: `{ account, machines: [...] }`
- Machines include: name, token (truncated), last_seen_at, revoked_at
- Does NOT include other participants' machines

**`GET /api/account/teams`**
- Auth: Clerk JWT
- Response: `{ teams: [{ id, name, agent_count, rule_count, participants: [{ email | "anonymous" }] }] }`
- Participants resolved via: team → token_teams → account_tokens → accounts

**`DELETE /api/account/machines/:token`**
- Auth: Clerk JWT
- Validation: token must belong to the caller's account
- Action: Sets `revoked_at`, deletes `token_teams`, messages GenServer
- Response: `{ status: "revoked" }`

**`POST /api/account/reassociate`**
- Auth: Clerk JWT + ed25519 signature (both)
- Body: `{ new_token: "tb_ak_..." }`
- Validation: new_token must be linked to the caller's account
- Action: Copies all `token_teams` from the account's other (non-revoked) tokens to `new_token`. Immediate, no hold.
- Response: `{ reassociated: 3 }`

## Security Model

### Threat: Attacker knows a machine token

Machine tokens are derived from public keys and are not secret. But:
- API calls require ed25519 signature with the private key
- Linking to a Clerk account requires both ed25519 sig AND Clerk JWT
- An attacker can't link your token to their account without your private key

### Threat: Brute-force device user_code

- 8 characters from restricted alphabet (uppercase + digits, no ambiguous chars): ~852 billion combinations
- Per-IP rate limit: 10 attempts per minute
- Global per-code limit: 5 failed attempts → code invalidated
- Expires after 15 minutes
- Polling endpoint bound to originating token

### Threat: Compromised Clerk account used for team theft

Attack: phish Clerk password → link new keypair → reassociate teams.
Mitigation:
- Clerk supports built-in 2FA (primary defense)
- Email notification on new machine linking and reassociation (user can revoke)
- Reassociation logged and visible in dashboard
- Same security model as GitHub/Vercel — account compromise is mitigated by 2FA, not artificial delays

### Threat: Revocation bypass via GenServer restart

Fixed: revocation deletes `token_teams` rows in the database. GenServer reloads from DB on restart, so revoked tokens stay revoked.

### Threat: CSRF on web verification

Fixed: `/auth/verify` uses LiveView websocket, which has built-in CSRF protection via the socket connection.

### Threat: JWT algorithm confusion

Fixed: `VerifyClerkJWT` plug pins algorithm to RS256, validates `iss`, `exp`, and `aud` claims. Uses `JOSE.JWT.verify_strict/3`.

### What doesn't change

- All existing API endpoints (sync, push, pull, teams) use ed25519 signatures only
- `teambridge join` works without any account
- The GenServer/in-memory sync layer is unchanged
- Invite codes work exactly the same

## Clerk Integration Details

### Server-side (Elixir)

**New Plug: `VerifyClerkJWT`**
- Extracts Bearer token from Authorization header
- Verifies JWT signature against Clerk JWKS (cached, 5-minute TTL)
- Pins algorithm to RS256 only
- Validates `iss` (Clerk instance domain), `exp` (with 30s skew), `aud`
- Extracts `sub` (clerk_user_id) and `email`
- Assigns `:clerk_user_id` and `:clerk_email` to conn

### Client-side (Web)

Clerk hosted sign-in page (redirect flow). The `/auth/verify` page redirects to Clerk sign-in if not authenticated, then back to the verification page with the user_code pre-filled if provided via URL parameter.

### CLI-side

No Clerk SDK needed. The CLI just:
1. Opens a browser URL
2. Polls a device code endpoint
3. Stores the result locally in `~/.teambridge/config.json`

## Implementation Plan

### Phase 1: Foundation (DB + API)
1. Add `accounts` and `account_tokens` migrations
2. Add `Account` and `AccountToken` schemas
3. Add `owner_account_id` to teams migration
4. Add `VerifyClerkJWT` plug
5. Add device auth endpoints + ephemeral storage (GenServer with periodic sweep)
6. Add device request rate limiting (per-IP + per-code)
7. Add email notifications for new machine linking and reassociation (via Clerk or simple SMTP)

### Phase 2: CLI
7. Add `teambridge login` command (device auth flow with browser open)
8. Add inline account linking prompt to `teambridge join` and `teambridge init`
9. Add account info to `~/.teambridge/config.json`
10. Add machine name auto-detection (`os.hostname()`) with `--name` override

### Phase 3: Web
11. Add Clerk JS to root layout (hosted sign-in redirect)
12. Add `/auth/verify` LiveView page (device code confirmation)
13. Add `/dashboard` LiveView page (your machines + your teams + team participants)
14. Add machine revocation UI

### Phase 4: Recovery
15. Add reassociation endpoint (immediate, no hold)
16. Add recovery flow in CLI (detect old teams, prompt to reassociate)

## Decisions

1. **Clerk pricing** — Free tier allows 10K MAU. Sufficient for launch.
2. **Machine naming** — Auto-detect OS hostname (`os.hostname()`), allow override via `teambridge login --name "work laptop"`.
3. **Team ownership** — Deferred. No owner/member distinction for now. Teams are collaborative, anyone who joined can use them. Add ownership and permissions later when needed.
4. **Revocation propagation** — Delete `token_teams` rows in DB + send message to GenServer for immediate in-memory removal.
5. **Multi-user teams** — Supported naturally via invite codes. No special handling needed. Privacy boundary: machines are private to accounts, team participants are visible to each other.
6. **`skip_auth` in dev** — Remove `:dev` from `skip_auth_allowed` in `VerifySignature` plug. Only `:test` should bypass auth.
