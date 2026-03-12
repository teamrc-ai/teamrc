# teamrc

Sync AI agent teams across platforms with a single, version-controlled source of truth.

## Quick Start

```bash
# Create a new team
npx @teamrc/cli init

# Join an existing team
npx @teamrc/cli join <invite-token>

# Edit .teamrc.yaml, then apply
npx @teamrc/cli apply
```

## Architecture

```
.teamrc.yaml     (source of truth, version-controlled)
       |
  CLI commands   (init, apply, export, sync)
       |
  relay server   (cross-machine sync)
       |
platform adapters (Claude Code, Cursor, Codex, OpenClaw, Gemini)
       |
native agent files (.claude/agents/, .cursor/rules/, etc.)
```

**Priority chain:** `.teamrc.yaml` > platform folders

## .teamrc.yaml

The canonical team definition. Check this into version control.

```yaml
name: my-team
teamId: <uuid>          # assigned by relay on init/join
relay: http://localhost:4000
platforms:
  - claude-code
  - cursor

members:
  - name: architect
    role: Design system architecture
    skills:
      - code-review
  - name: implementer
    role: Write implementation code
    soul: "You are a meticulous coder who writes tests first."

skills:
  - id: code-style
    title: Code Style
    alwaysApply: true
    globs: ["*.ts", "*.js"]
    body: |
      Use eslint + prettier defaults.
  - id: deploy
    description: Deploy to staging
    body: |
      Run the deployment pipeline...
```

Fields:
- **name**: Team name (alphanumeric, spaces, hyphens, underscores; max 64 chars)
- **teamId**: UUID assigned by the relay server
- **relay**: Relay server URL for cross-machine sync
- **platforms**: Target platforms (`claude-code`, `cursor`, `codex`, `gemini`, `openclaw`)
- **members**: Array of agents (max 20)
  - **name**: Agent name (alphanumeric, hyphens, underscores; max 64 chars)
  - **role**: One-line role description
  - **soul**: Optional custom persona or instructions
  - **skills**: Optional list of skill IDs to assign to this agent
- **skills**: Array of shared skills and conventions (max 50)
  - **id**: Skill identifier (alphanumeric, hyphens, underscores; max 64 chars)
  - **title**: Display name
  - **description**: What the skill does
  - **globs**: Optional file patterns for scoped activation (written as native rules)
  - **alwaysApply**: Whether skill is always active (written as native rules; default: false)
  - **userInvocable**: Whether the skill can be invoked on demand
  - **body**: Skill content (inline string or `{ source: "./path" }`)

## CLI Commands

| Command | Description |
|---------|-------------|
| `teamrc init` | Detect platform, create agents, write `.teamrc.yaml`, connect to relay |
| `teamrc join <token>` | Join an existing team and set up locally |
| `teamrc clone <token>` | Copy a team locally without joining sync. `--name` to override name |
| `teamrc apply` | Apply `.teamrc.yaml` to local platform(s) |
| `teamrc sync` | One-time sync with relay server |
| `teamrc push` | Push local state and knowledge to relay |
| `teamrc pull` | Pull latest team from relay and apply locally |
| `teamrc diff` | Show differences between local and relay. `--json` for machine-readable output |
| `teamrc status` | Show current config and team state. `--json` for machine-readable output |
| `teamrc export` | Export team from relay to `.teamrc.yaml` |
| `teamrc import <platform>` | Import existing platform config into `.teamrc.yaml` |
| `teamrc dashboard` | Open the current team in your browser |
| `teamrc invite` | Generate an invite code for your team |
| `teamrc share` | Toggle team visibility (public/private) |
| `teamrc claim <secret>` | Claim ownership of a team |
| `teamrc add-member` | Add a member interactively from the catalog |
| `teamrc list-templates` | List available team templates |
| `teamrc list-agents` | List available agent templates |
| `teamrc whoami` | Show local identity (token, machine, account, team) |
| `teamrc doctor` | Run health checks on config, relay, auth, and team state |
| `teamrc daemon` | Start background sync. `--sync-mode <all\|knowledge\|none>` (default: knowledge) |
| `teamrc login` | Link this machine to an account via device auth |
| `teamrc erase` | Erase a token and its data from the relay |
| `teamrc delete` | Remove all teamrc setup from this machine |

## Platforms

- **Claude Code**: Agents in `.claude/agents/trc-*.md` with YAML frontmatter. Skills with `alwaysApply`/`globs` as `.claude/rules/trc-*.md`. On-demand skills as `.claude/skills/trc-*/SKILL.md`. Updates `CLAUDE.md` with team section.
- **Cursor**: Subagents in `.cursor/agents/trc-*.md`. Skills with `alwaysApply`/`globs` as `.cursor/rules/trc-*.mdc`. On-demand skills as `.cursor/skills/trc-*/SKILL.md`. Routing via `.cursor/AGENTS.md`.
- **Codex**: Agent TOML configs in `.codex/agents/trc-*.toml`. Registered in `.codex/config.toml`. Routing via `AGENTS.md`.
- **OpenClaw**: Each agent gets a workspace at `~/.openclaw/workspace-trc-*/` with `AGENTS.md` and `SOUL.md`. Skills in `~/.openclaw/skills/trc-*/SKILL.md`. Registered in `~/.openclaw/openclaw.json`.
- **Gemini**: Agents in `.gemini/agents/trc-*.md` with YAML frontmatter. Skills as `.agents/skills/trc-*/SKILL.md` (Gemini CLI) and `.agent/skills/trc-*/SKILL.md` (Antigravity). Updates `GEMINI.md` with team section.

## Self-Hosting

### Docker (recommended)

```bash
# Clone and start with Docker Compose
git clone <repo-url> && cd teamrc
cp .env.example .env
# Edit .env and set SECRET_KEY_BASE, SESSION_SIGNING_SALT, LIVE_VIEW_SIGNING_SALT, SESSION_ENCRYPTION_SALT
docker compose up
```

The relay server will be available at `http://localhost:4000`. Postgres is included.

For production deployments (Coolify, etc.), set the required environment variables and point at the `Dockerfile`. See `.env.example` for the full list.

### Without Docker

```bash
# Requires Elixir 1.18+, PostgreSQL
cd teamrc
mix setup
mix phx.server  # http://localhost:4000
```

Point the CLI at your relay with `TEAMRC_RELAY=http://your-host:4000` or set `relay:` in `.teamrc.yaml`.

## Security

- Ed25519 authentication with timestamp-signed requests
- Agent names validated with strict regex before filesystem use
- YAML file size limited to 256KB, max 20 members
- Team names and roles sanitized in all template outputs
- Daemon sync operations are serialized with a mutex
- Invite codes are multi-use with 144-bit entropy and 24h TTL
- Every content change tracks `pushed_by` token for attribution
- Daemon defaults to knowledge-only sync mode (agent definitions require explicit `teamrc sync`)
- Sync state capped at 50MB per team
- Skills capped at 50 per team and 10KB per skill body
- Clerk JWT validation for account endpoints (fail-closed when configured)
- See security test suite for coverage of auth, ownership, and validation

**Important:** Treat `.teamrc.yaml` as a trusted configuration file (like `.env`). The `soul` field controls agent behavior, so review YAML changes in PRs just as you would review code changes.
