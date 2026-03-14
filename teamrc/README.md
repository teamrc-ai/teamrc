# teamrc relay

Elixir/Phoenix backend for teamrc. Handles cross-machine sync, team management, and the web UI.

## Setup

### Option A: Docker (from repo root)

```bash
docker compose up  # http://localhost:4000
```

### Option B: Elixir

Requires Elixir 1.18+ and PostgreSQL.

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

- **GenServer** (`Teamrc.Teams`): In-memory sync state. Stores file hashes per platform, file content (24h TTL), and token-to-team mapping.
- **PostgreSQL** (via Ecto): Persistent storage for teams, members, invites, and account tokens.
- **LiveView**: Web UI for team creation with template catalog.
- **Ed25519 signature verification**: All API endpoints authenticated via the `VerifySignature` plug.
- **phx.gen.auth + UeberAuth**: Session-based auth with GitHub/Google OAuth for user accounts (dashboard, machine management, recovery).

## API Pipelines

| Pipeline | Auth | Endpoints |
|----------|------|-----------|
| `:api` | Ed25519 signature + rate limit | `/api/sync`, `/api/push`, `/api/join`, `/api/teams`, `/api/teams/preview`, `/api/teams/invite`, `/api/log` |
| `:session_api` | Session auth + rate limit | `/api/account`, `/api/account/teams` |
| `:session_and_signature_api` | Session + Ed25519 signature | `/api/account/reassociate` |

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
| `DNS_CLUSTER_QUERY` | DNS discovery query for clustering |

Dev config: `config/dev.exs`. Production runtime config: `config/runtime.exs`.
