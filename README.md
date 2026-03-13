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
| `teamrc share` | Make team public and get a shareable link. `--off` to make private |
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

Each platform adapter generates native files so the AI tool discovers agents without extra configuration. All managed files use the `trc-` prefix.

| Platform | Agents | Skills/Rules | Routing | Scope |
|----------|--------|-------------|---------|-------|
| **Claude Code** | `.claude/agents/trc-*.md` | `.claude/rules/trc-*.md`, `.claude/skills/trc-*/SKILL.md` | `CLAUDE.md` | project + global |
| **Cursor** | `.cursor/agents/trc-*.md` | `.cursor/rules/trc-*.mdc`, `.cursor/skills/trc-*/SKILL.md` | `.cursor/AGENTS.md` | project |
| **Codex** | `.codex/agents/trc-*.toml` | `.agents/skills/trc-*/SKILL.md` | `AGENTS.md`, `.codex/config.toml` | project |
| **Gemini** | `.gemini/agents/trc-*.md` | `.agents/skills/trc-*/SKILL.md`, `.agent/skills/trc-*/SKILL.md` | `GEMINI.md` | project + global |
| **OpenClaw** | `~/.openclaw/agents/trc-*.md` | `~/.openclaw/skills/trc-*/SKILL.md` | `~/.openclaw/openclaw.json` | global |

OpenClaw requires explicit subagent spawn permissions. teamrc configures `subagents.allowAgents` in `openclaw.json` so every team agent can delegate to every other team agent.

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

## Sharing

Make your team public so anyone can view and clone it:

```bash
teamrc share          # makes team public, outputs share URL
teamrc share --off    # makes team private again
```

Public teams get a shareable page at `/t/<clone_token>` showing the team composition, agents, and skills. Anyone with the link can clone it:

```bash
npx @teamrc/cli clone <clone_token>
```

Knowledge files are never shared. Skill body content is redacted on public pages.

You can also share from the web UI via the **Share** button on the team dashboard.

## Security

See the security test suites for coverage of auth, ownership, and input validation.
