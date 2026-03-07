# teamrc relay

Elixir/Phoenix backend for teamrc — handles cross-machine sync, team management, and the web UI.

## Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server  # http://localhost:4000
```

Requires Elixir 1.18+, PostgreSQL.

## Architecture

- **GenServer** (`Teamrc.Teams`) — In-memory sync state: file hashes per platform, file content (24h TTL), token-to-team mapping
- **PostgreSQL** (via Ecto) — Persistent storage: teams, members, invites, account tokens
- **LiveView** — Web UI for team creation with templates
- **Ed25519 signature verification** — All API endpoints authenticated via `VerifySignature` plug
- **Clerk JWT** — Optional account layer for linking machines to user accounts

## API Pipelines

| Pipeline | Auth | Endpoints |
|----------|------|-----------|
| `:api` | Ed25519 signature + rate limit | `/api/sync`, `/api/push`, `/api/join`, `/api/teams` |
| `:clerk_api` | Clerk JWT + rate limit | `/api/account`, `/api/account/teams` |
| `:clerk_and_signature_api` | Both | `/api/account/reassociate` |

## Testing

```bash
mix test                     # Run all tests
mix test --failed            # Re-run failures
MIX_ENV=test mix ecto.reset  # Reset test DB
```

## Configuration

- `config/dev.exs` — Dev settings (localhost binding, CORS origins)
- `config/runtime.exs` — Production env vars: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `SESSION_SIGNING_SALT`, `LIVE_VIEW_SIGNING_SALT`, `CLERK_ISSUER`, `CLERK_JWKS_URL`
