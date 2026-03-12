# teamrc relay

Elixir/Phoenix backend for teamrc — handles cross-machine sync, team management, and the web UI.

## Setup

### Docker

```bash
# From the repo root:
cp .env.example .env
# Edit .env — set SECRET_KEY_BASE, salts, etc.
docker compose up
```

### Without Docker

Requires Elixir 1.18+, PostgreSQL.

```bash
mix deps.get
mix ecto.setup
mix phx.server  # http://localhost:4000
```

## Architecture

- **GenServer** (`Teamrc.Teams`) — In-memory sync state: file hashes per platform, file content (24h TTL), token-to-team mapping
- **PostgreSQL** (via Ecto) — Persistent storage: teams, members, invites, account tokens
- **LiveView** — Web UI for team creation with template catalog
- **Ed25519 signature verification** — All API endpoints authenticated via `VerifySignature` plug
- **Clerk JWT** — Optional account layer for linking machines to user accounts (dashboard, machine management, recovery)

## API Pipelines

| Pipeline | Auth | Endpoints |
|----------|------|-----------|
| `:api` | Ed25519 signature + rate limit | `/api/sync`, `/api/push`, `/api/join`, `/api/teams`, `/api/teams/preview`, `/api/teams/invite`, `/api/log` |
| `:clerk_api` | Clerk JWT + rate limit | `/api/account`, `/api/account/teams` |
| `:clerk_and_signature_api` | Both | `/api/account/reassociate` |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/teams` | Create a new team |
| `GET` | `/api/teams/:token` | Get team for a token |
| `POST` | `/api/teams/preview` | Preview a team by invite code (read-only, no join) |
| `POST` | `/api/teams/invite` | Generate a new invite code for your team |
| `POST` | `/api/join` | Join a team by invite code |
| `POST` | `/api/sync` | Sync local state with relay (push + pull) |
| `GET` | `/api/sync/check` | Check if remote has changes since timestamp |
| `POST` | `/api/push` | Push team knowledge entries |
| `GET` | `/api/log` | Get recent sync activity with attribution |
| `POST` | `/api/auth/device` | Start device auth flow |
| `GET` | `/api/auth/device/:device_code` | Poll device auth status |

## Testing

```bash
mix test                     # Run all tests
mix test --failed            # Re-run failures
MIX_ENV=test mix ecto.reset  # Reset test DB
```

## Configuration

### Required (production)

| Env var | Description |
|---------|-------------|
| `DATABASE_URL` | PostgreSQL connection string (`ecto://USER:PASS@HOST/DATABASE`) |
| `DATABASE_SSL` | Enable SSL for database connections (default: `true`) |
| `SECRET_KEY_BASE` | Cookie signing key (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Public hostname for URL generation |
| `SESSION_SIGNING_SALT` | Session cookie signing salt |
| `LIVE_VIEW_SIGNING_SALT` | LiveView signing salt |
| `SESSION_ENCRYPTION_SALT` | Session cookie encryption salt |

### Optional (Clerk account linking)

Without these, teamrc works fully — team sync, CLI, invites all function. Clerk adds: user dashboard, machine management, account recovery.

| Env var | Description |
|---------|-------------|
| `CLERK_PUBLISHABLE_KEY` | Clerk frontend key (enables Sign In button) |
| `CLERK_JWKS_URL` | Clerk JWKS endpoint for JWT verification |
| `CLERK_ISSUER` | Clerk JWT issuer |
| `CLERK_AUDIENCE` | Clerk JWT audience (optional) |

### Other

| Env var | Description |
|---------|-------------|
| `PORT` | HTTP port (default: `4000`) |
| `POOL_SIZE` | Database connection pool size (default: `10`) |
| `DNS_CLUSTER_QUERY` | DNS discovery query for clustering |

Dev config: `config/dev.exs`. Production runtime config: `config/runtime.exs`.
