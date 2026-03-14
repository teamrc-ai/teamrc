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

```bash
# Or create a local-only team (no server required)
npx @teamrc/cli init --local
```

## Local-Only Mode

teamrc works without an internet connection. Use `--local` with init to create a team that lives entirely on your machine:

```bash
npx @teamrc/cli init --local
```

Local teams support `apply`, `import`, `status`, `delete`, and all template/catalog commands. To connect a local team to teamrc.ai later for cross-machine sync:

```bash
teamrc push
```

This registers the team on the relay and enables `sync`, `pull`, `invite`, and all collaboration features.

## Architecture

```
.teamrc.yaml     (source of truth, version-controlled)
       |
  CLI commands   (init, apply, sync, push)
       |
platform adapters (Claude Code, Cursor, Codex, OpenClaw, Gemini)
       |
native agent files (.claude/agents/, .cursor/rules/, etc.)
       |
  relay server   (optional  --  cross-machine sync via teamrc.ai)
```

**Priority chain:** `.teamrc.yaml` > platform folders

## .teamrc.yaml

The canonical team definition. Check this into version control.

```yaml
name: my-team
# teamId and relay are set when connected to teamrc.ai
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
- **teamId**: UUID assigned by the relay server (absent for local-only teams)
- **relay**: Relay server URL for cross-machine sync (absent for local-only teams)
- **platforms**: Target platforms (`claude-code`, `cursor`, `codex`, `gemini`, `openclaw`)
- **members**: Array of agents (max 20)
  - **name**: Agent name (alphanumeric, hyphens, underscores; max 64 chars)
  - **role**: One-line role description
  - **description**: Optional capability-based description for AI platform routing (e.g. `"Builds UI components. Use when tasks involve React or CSS."`)
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
| `teamrc init` | Create a new team. `--local` to skip relay connection |
| `teamrc join <token>` | Join an existing team and set up locally |
| `teamrc clone <token>` | Copy a team locally without joining sync. `--name` to override name |
| `teamrc apply` | Apply `.teamrc.yaml` to local platform(s) |
| `teamrc sync` | One-time sync with relay server |
| `teamrc push` | Push local state to relay. Connects a local-only team on first push |
| `teamrc pull` | Pull latest team from relay and apply locally |
| `teamrc diff` | Show differences between local and relay. `--json` for machine-readable output |
| `teamrc status` | Show current config and team state. `--json` for machine-readable output |
| `teamrc export` | Export team from relay to `.teamrc.yaml` |
| `teamrc import <platform>` | Import existing platform config into `.teamrc.yaml` |
| `teamrc dashboard` | Create a temporary invite link and open the team dashboard. `--ttl <hours>` (default: 24) |
| `teamrc invite` | Generate an invite code for your team |
| `teamrc share` | Make team public and get a shareable link. `--off` to make private |
| `teamrc claim <secret>` | Claim ownership of a team |
| `teamrc add-member` | Add a member interactively from the catalog |
| `teamrc list-templates` | List available team templates |
| `teamrc list-agents` | List available agent templates |
| `teamrc whoami` | Show local identity (token, machine, account, team) |
| `teamrc doctor` | Run health checks on config, relay, auth, and team state |
| `teamrc daemon` | *(Coming soon)* Start background sync |
| `teamrc login` | Link this machine to an account via device auth |
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

### Install Elixir

macOS:
```bash
brew install elixir
```

Ubuntu/Debian:
```bash
sudo apt install elixir erlang
```

Or use [asdf](https://asdf-vm.com/) for version management:
```bash
asdf plugin add erlang && asdf plugin add elixir
asdf install erlang 27.2 && asdf install elixir 1.18.2-otp-27
```

See the [Elixir install guide](https://elixir-lang.org/install.html) for other platforms.

### Run the relay

Requires Elixir 1.18+ and PostgreSQL.

```bash
cd teamrc
mix setup
mix phx.server  # http://localhost:4000
```

Point the CLI at your relay with `TEAMRC_RELAY=http://localhost:4000` or set `relay:` in `.teamrc.yaml`.

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

Sharing via the CLI requires a linked account. Run `teamrc login` first.

## Access Model

| Role | How you get it | What you can do |
|------|---------------|-----------------|
| **Owner** | Create team via web UI (signed in), or `teamrc claim <secret>` | Full control: edit, share, toggle visibility, manage invites |
| **Participant** | `teamrc join <invite-code>` | Edit agents/skills, push/pull/sync, generate invites |
| **Viewer** | Visit a public team's share link | Read-only view, can clone |

Teams are **private by default**. Only participants and owners can see a private team's page.

Ownership is optional for basic usage. To control visibility or share your team, claim ownership with `teamrc claim` (requires `teamrc login` first).

## Security

See the security test suites for coverage of auth, ownership, and input validation.
