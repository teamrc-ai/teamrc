# teamrc

Sync multi-agent teams across platforms with a shared, version-controllable source of truth.

## Quick Start

```bash
# Create a new team
npx teamrc init

# Join an existing team
npx teamrc join <invite-token>

# Edit .teamrc.yaml, then apply
npx teamrc apply
```

## Architecture

```
.teamrc.yaml     (source of truth, version-controllable)
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
members:
  - name: architect
    role: Design system architecture
  - name: implementer
    role: Write implementation code
    soul: "You are a meticulous coder who writes tests first."

rules:
  - id: code-style
    title: Code Style
    globs: ["*.ts", "*.js"]
    body: |
      Use eslint + prettier defaults.

skills:
  - id: deploy
    description: Deploy to staging
    body: |
      Run the deployment pipeline...
```

Fields:
- **name** — Team name (alphanumeric, spaces, hyphens, underscores; max 64 chars)
- **members** — Array of agents (max 100)
  - **name** — Agent name (alphanumeric, hyphens, underscores; max 64 chars)
  - **role** — One-line role description
  - **soul** — Optional custom persona/instructions
- **rules** — Array of shared coding conventions (max 50)
  - **id** — Rule identifier (alphanumeric, hyphens; max 64 chars)
  - **title** — Display name
  - **globs** — Optional file patterns for scoped activation
  - **alwaysApply** — Whether rule is always active (default: false)
  - **body** — Rule content (inline string or `{ source: "./path" }`)
- **skills** — Array of reusable capabilities (max 50)
  - **id** — Skill identifier
  - **description** — What the skill does
  - **body** — Skill content

## CLI Commands

| Command | Description |
|---------|-------------|
| `teamrc init` | Detect platform, create agents, write `.teamrc.yaml`, connect to relay |
| `teamrc join <token>` | Join an existing team and set up locally. `--no-sync` for local-only |
| `teamrc clone <token>` | Copy a team locally without joining sync. `--name` to override name |
| `teamrc invite` | Generate an invite code for your team. `--ttl <hours>` (default: 24, max: 168) |
| `teamrc apply` | Apply `.teamrc.yaml` to local platform(s) |
| `teamrc export` | Export team from relay to `.teamrc.yaml` |
| `teamrc sync` | One-time sync with relay server |
| `teamrc push` | Push team knowledge to relay |
| `teamrc diff` | Show differences between local and relay. `--json` for machine-readable output |
| `teamrc status` | Show current config and team state. `--json` for machine-readable output |
| `teamrc whoami` | Show local identity (token, machine, account, team). No network calls |
| `teamrc log` | Show recent sync activity with attribution. `--limit <n>` (default: 20) |
| `teamrc doctor` | Run health checks on config, relay, auth, and team state |
| `teamrc daemon` | Start background sync. `--sync-mode <all\|knowledge\|none>` (default: knowledge) |
| `teamrc login` | Link this machine to a Clerk account via device auth |
| `teamrc delete` | Remove all teamrc setup from this machine |

## Platforms

- **Claude Code** — Agents in `.claude/agents/trc-*.md` with YAML frontmatter. Rules as `.claude/rules/trc-*.md`. Skills as `.claude/skills/trc-*/SKILL.md`. Updates `CLAUDE.md` with team section.
- **Cursor** — Subagents in `.cursor/agents/trc-*.md`. Rules as `.cursor/rules/trc-*.mdc`. Skills as `.cursor/skills/trc-*/SKILL.md`. Routing via `.cursor/AGENTS.md`.
- **Codex** — Agent TOML configs in `.codex/agents/trc-*.toml`. Registered in `.codex/config.toml`. Routing via `AGENTS.md`.
- **OpenClaw** — Agents in `.agents/agents/trc-*.md` with YAML frontmatter. Skills as `.agents/skills/trc-*/SKILL.md`. Routing via `AGENTS.md`.
- **Gemini** — Agents in `.gemini/agents/trc-*.md` with YAML frontmatter. Skills as `.gemini/skills/trc-*/SKILL.md`. Updates `GEMINI.md` with team section.

## Relay

Elixir/Phoenix server for cross-machine sync. Stores team definitions in PostgreSQL, sync state in memory (24h TTL).

Optional account layer: Clerk JWT auth for linking machines to accounts via device auth flow.

```bash
cd teamrc
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
- Invite codes are multi-use with 144-bit entropy and 24h TTL
- Sync attribution: every content change tracks `pushed_by` token for accountability
- Daemon defaults to knowledge-only sync mode (agent definitions require explicit `teamrc sync`)
- Content cap: 50MB per team for sync state
- Rules/skills validated: max 50 each, max 10KB per rule body
- Clerk JWT validation for account endpoints (fail-closed)
- Production config validated at boot (CLERK_ISSUER, signing salts)
- See `docs/security-audit.md` for full audit

## Security Note

Treat `.teamrc.yaml` as a trusted configuration file (like `.env`). The `soul` field controls agent behavior — review YAML changes in PRs just as you would review code changes.
