# TeamBridge

Sync multi-agent teams across platforms with a shared, version-controllable source of truth.

## Quick Start

```bash
# Create a new team
npx teambridge init

# Join an existing team
npx teambridge join <invite-token>

# Edit agent-team.yaml, then apply
npx teambridge apply
```

## Architecture

```
agent-team.yaml  (source of truth, version-controllable)
       ↓
  CLI commands   (init, apply, pull, export)
       ↓
  relay server   (cross-machine sync)
       ↓
platform adapters (Claude Code, OpenClaw)
       ↓
native agent files (.claude/agents/, ~/.openclaw/workspaces/)
```

**Priority chain:** `agent-team.yaml` > relay > platform folders

## agent-team.yaml

The canonical team definition. Check this into version control.

```yaml
name: my-team
members:
  - name: architect
    role: Design system architecture
  - name: implementer
    role: Write implementation code
    soul: "You are a meticulous coder who writes tests first."
```

Fields:
- **name** — Team name (alphanumeric, spaces, hyphens, underscores; max 64 chars)
- **members** — Array of agents (max 100)
  - **name** — Agent name (alphanumeric, hyphens, underscores; max 64 chars)
  - **role** — One-line role description
  - **soul** — Optional custom persona/instructions

## CLI Commands

| Command | Description |
|---------|-------------|
| `teambridge init` | Detect platform, create agents, write `agent-team.yaml`, connect to relay |
| `teambridge join <token>` | Join an existing team and set up locally |
| `teambridge apply` | Apply `agent-team.yaml` to local platform(s) |
| `teambridge pull` | Pull team from relay → YAML → local platforms |
| `teambridge export` | Export team from relay to `agent-team.yaml` |
| `teambridge sync` | One-time sync with relay server |
| `teambridge push` | Push team knowledge to relay |
| `teambridge diff` | Show differences between local and relay |
| `teambridge status` | Show current config and team state |
| `teambridge daemon` | Start background sync (file watching + polling) |
| `teambridge delete` | Remove all TeamBridge setup from this machine |

## Platforms

- **Claude Code** — Agents written to `.claude/agents/tb-*.md` with YAML frontmatter. Updates `CLAUDE.md` with team section. Sync hook via `settings.json`.
- **OpenClaw** — Agents written to `~/.openclaw/workspaces/tb-*/` with `SOUL.md` and `AGENTS.md`. Registered in `openclaw.json`.

## Relay

Elixir/Phoenix server for cross-machine sync. Stores team definitions in PostgreSQL, sync state in memory (24h TTL).

```bash
cd teambridge
mix deps.get
mix ecto.setup
mix phx.server  # http://localhost:4000
```

## Security

- Ed25519 authentication with timestamp-signed requests
- Agent names validated with strict regex before filesystem use
- YAML file size limited to 256KB, max 100 members
- Team names and roles sanitized in all template outputs
- Daemon sync operations serialized with mutex
- See `docs/security-audit.md` for full audit

## Security Note

Treat `agent-team.yaml` as a trusted configuration file (like `.env`). The `soul` field controls agent behavior — review YAML changes in PRs just as you would review code changes.
