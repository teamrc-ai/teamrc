# teamrc relay

Elixir/Phoenix backend for teamrc. Handles cross-machine sync, team management, and the web UI.

## Setup

### Option A: Docker (from repo root)

```bash
docker compose up  # http://localhost:4000
```

### Option B: Elixir

Requires Elixir 1.15+ and PostgreSQL.

Install Elixir:

```bash
# macOS
brew install elixir

# Ubuntu/Debian
sudo apt install elixir erlang
```

See the [Elixir install guide](https://elixir-lang.org/install.html) for other platforms.

Run:

```bash
mix setup
mix phx.server  # http://localhost:4000
```

## Architecture

- **Ecto context** (`Teamrc.Teams`): Plain context module for all team CRUD operations. Queries Postgres directly, no in-memory state.
- **PostgreSQL** (via Ecto): Persistent storage for teams, members, invites, and account tokens.
- **WebSocket Channels**: Real-time knowledge sync (`KnowledgeChannel`) and task updates (`TasksChannel`) via Phoenix Channels.
- **LiveView**: Web UI for team creation with template catalog.
- **Ed25519 signature verification**: All API endpoints authenticated via the `VerifySignature` plug.
- **OAuth + phx.gen.auth**: Session-based auth with GitHub/Google OAuth (via UeberAuth) for user accounts (dashboard, machine management, recovery).

## API Pipelines

| Pipeline | Auth |
|----------|------|
| `:api` | Ed25519 signature + rate limit |
| `:auth_rate_limit` | Additional Bcrypt rate limiting for ownership claims |
| `:session_api` | Session auth + rate limit (account endpoints) |
| `:session_and_signature_api` | Session + Ed25519 signature |
| `:public_api` | No auth (clone endpoint) |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/teams` | Create or update a team |
| `GET` | `/api/teams/:token` | Get team for a token |
| `GET` | `/api/teams/:token/head` | Check team hash (lightweight) |
| `GET` | `/api/teams/all/:token` | Get all teams for a token |
| `POST` | `/api/teams/preview` | Preview a team by invite code |
| `POST` | `/api/teams/invite` | Generate invite code |
| `POST` | `/api/teams/view-token` | Create public view token |
| `POST` | `/api/teams/visibility` | Set team visibility |
| `POST` | `/api/teams/knowledge` | Push knowledge content |
| `POST` | `/api/teams/tasks` | Create a task |
| `GET` | `/api/teams/tasks/:token` | List tasks |
| `PATCH` | `/api/teams/tasks/:number` | Update task status |
| `POST` | `/api/teams/claim` | Claim team ownership |
| `POST` | `/api/join` | Join a team by invite code |
| `POST` | `/api/auth/device` | Start device auth flow |
| `GET` | `/api/auth/device/:device_code` | Poll device auth status |
| `GET` | `/api/teams/clone/:clone_token` | Clone team (public, no auth) |
| `DELETE` | `/token/:token/erase` | Erase token data |
| `GET` | `/api/account` | Get account info |
| `GET` | `/api/account/teams` | List account teams |
| `GET` | `/api/account/export` | Export account data |
| `DELETE` | `/api/account/machines/:token` | Revoke machine token |
| `DELETE` | `/api/account` | Delete account |
| `POST` | `/api/account/reassociate` | Reassociate machine token |

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
| `SECRET_KEY_BASE` | Cookie signing key (generate with `mix phx.gen.secret`) |
| `SESSION_SIGNING_SALT` | Session cookie signing salt |
| `LIVE_VIEW_SIGNING_SALT` | LiveView signing salt |
| `SESSION_ENCRYPTION_SALT` | Session cookie encryption salt |

### Optional (OAuth account linking)

Without these, teamrc works fully. Team sync, CLI, and invites all function. OAuth adds the user dashboard, machine management, and account recovery.

| Env var | Description |
|---------|-------------|
| `GITHUB_CLIENT_ID` | GitHub OAuth App client ID |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth App client secret |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |

### Other

| Env var | Description |
|---------|-------------|
| `PORT` | HTTP port (default: `4000`) |
| `POOL_SIZE` | Database connection pool size (default: `10`) |
| `PHX_HOST` | Public hostname for URL generation (default: `teamrc.ai`) |
| `DATABASE_SSL` | Enable SSL for database connections (default: `true`) |
| `DNS_CLUSTER_QUERY` | DNS discovery query for clustering |

Dev config: `config/dev.exs`. Production runtime config: `config/runtime.exs`.
