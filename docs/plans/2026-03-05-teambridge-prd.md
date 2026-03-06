# teamrc PRD

**Product Requirements Document**
**Version:** v0.4
**Date:** 2026-03-05
**Status:** MVP Complete
**Last Updated:** 2026-03-05

---

## 1. Overview

teamrc is a portable specification and synchronization tool for AI agent teams.

Developers define their agent team once in a project file (`agent-team.yaml`). teamrc then:

1. Applies the team to local agent platforms (Claude Code, OpenClaw, etc.)
2. Keeps agent teams synchronized across machines using a lightweight relay

The goal is to make agent teams portable, version controlled, and automatically synced across machines.

## 2. Problem

Developers using AI agent tools frequently work across multiple platforms and multiple machines. Current problems:

- **Agent configuration duplication** — teams must be recreated manually on each machine
- **Configuration drift** — agent roles diverge across platforms
- **Non-reproducible environments** — new developers cannot easily recreate the same agent team
- **Missing cross-machine synchronization** — changes made on one machine are not reflected elsewhere

## 3. Solution

teamrc introduces:

- A portable team specification (`agent-team.yaml`)
- A CLI tool (`npx teamrc`)
- A lightweight relay for cross-machine synchronization

## 4. Key Principles

- **Git remains the source of truth** — team definitions live in the repo
- **Relay is stateless for sync** — sync data (hashes, content) is in-memory only; Postgres stores teams and invites
- **CLI first** — all functionality works from the CLI
- **No accounts required** — identity is Ed25519 keypair per machine, team membership via invite codes
- **Automatic synchronization** — daemon watches files and polls relay every 2 minutes
- **Security first** — Ed25519 signed requests, replay protection, rate limiting, input validation

## 5. Core User Experience

### 5.1 Create a Team (Web UI)

Visit the teamrc web UI (LiveView). Users:

1. Choose from team templates (fullstack, backend, security, marketing, research, devops, custom)
2. Customize team name and members (name + role for each)
3. Click "Create Team"
4. Receive an invite code (`trc_inv_...`) with a ready-to-run join command

### 5.2 Join a Team

```bash
npx teamrc join trc_inv_XD3luzjtqCI7... --relay http://relay:4000
```

teamrc:
1. Detects installed platforms (if multiple found, asks which to set up — or both)
2. Generates Ed25519 keypair (stored at `~/.teamrc/key`)
3. Downloads team definition from relay
4. Writes `agent-team.yaml` locally
5. For each selected platform:
   - Asks scope (project vs global) for Claude Code
   - Creates platform-native agent files (e.g., `.claude/agents/tb-*.md`)
   - Installs sync hooks
6. Saves configuration

Example output with multiple platforms:

```
Multiple platforms detected:
  1) claude-code
  2) openclaw
  3) Both

Which platform? [1-3]: 3

Joined team: fraudstory
Created agent-team.yaml.

Setting up claude-code...
Where should this team be available?
  1) This project only (creates agents in .claude/agents/ and updates CLAUDE.md)
  2) All projects (creates agents in ~/.claude/agents/)
Choice [1/2]: 1
  claude-code configured.

Setting up openclaw...
  openclaw configured.

Configuration saved.
```

Invites are multi-use — the same invite code works on multiple machines until it expires (24 hours).

### 5.3 Initialize from Existing Agents

```bash
npx teamrc init --relay http://relay:4000
```

For users who already have agents configured locally. teamrc:
- Detects platforms (prompts if multiple)
- Reads existing agents and generates `agent-team.yaml`
- Applies to all selected platforms' native format
- Creates team on relay
- Installs hooks and saves config

### 5.4 Automatic Synchronization

After setup, synchronization is automatic via a background daemon:

```
local file change detected (chokidar)
  -> compute hash
  -> POST /api/sync with hashes + changed content
  -> relay stores and distributes
  -> other machines pick up on next poll (every 2 minutes)
  -> write changes locally
  -> regenerate platform-native agent files if agent-team.yaml changed
```

When the daemon receives a remote `agent-team.yaml` change, it also regenerates platform-native agent files (e.g., `.claude/agents/tb-*.md`) so the agents are immediately available.

No persistent connections. Pure HTTP polling. Scales to millions of users.

### 5.5 Team Knowledge

Agents are instructed (via CLAUDE.md) to read and write to `.claude/team-knowledge.md`. This file:
- Contains shared findings, decisions, and debugging insights from all agents across all machines
- Is synced automatically by the daemon (append-only merge — no data loss)
- Is separate from individual agent memory (doesn't interfere)

The CLAUDE.md section written by teamrc tells agents:

> Shared findings and decisions are stored in `.claude/team-knowledge.md`. Read this file at the start of every session for context from other agents and machines. When you discover something important, append it to this file so other team members can benefit.

### 5.6 Offline Commands

```bash
teamrc apply    # Apply agent-team.yaml to local platform (no relay needed)
teamrc diff     # Compare local vs relay state
teamrc status   # Show config, sync state, team info
teamrc sync     # Manual one-shot sync
```

### 5.7 CLI Distribution

The CLI is distributed via npm:

```bash
npx teamrc                  # Run directly (no install)
npm install -g teamrc       # Or install globally
npm pack && npm install -g ./teamrc-0.1.0.tgz  # Or from tarball (no registry needed)
```

## 6. Team Definition File

The canonical source of truth, living in the repository:

```yaml
# agent-team.yaml
name: fraudstory

agents:
  - name: architect
    role: Design system architecture

  - name: implementer
    role: Write production code

  - name: reviewer
    role: Review correctness and security
    soul: |
      You are a security-focused reviewer.
      Always check for OWASP top 10 vulnerabilities.
```

Constraints:
- Team name: required, lowercase alphanumeric + hyphens/underscores
- Agents: at least one required
- Each agent: name (required), role (required), soul (optional multiline)
- Duplicate agent names rejected

## 7. System Architecture

```
Machine A                    Machine B
Claude Code + OpenClaw       OpenClaw

teamrc daemon            teamrc daemon
  chokidar watcher             chokidar watcher
  2-min poll loop              2-min poll loop
        |                            |
        +--- HTTP polling ---+-------+
                             |
                     +-------v-------+
                     |     Relay     |
                     |   (Phoenix)   |
                     |               |
                     | Postgres:     |  In-Memory (GenServer):
                     |  - teams      |  - file hashes per platform
                     |  - members    |  - file content (24h TTL)
                     |  - invites    |  - token -> team mapping
                     |               |  - last_updated_at per team
                     +---------------+
```

A single machine can have multiple platforms. The CLI detects all installed platforms and can configure them all at once.

## 8. Components

### 8.1 CLI

Commands:

| Command | Description |
|---------|-------------|
| `teamrc init` | Detect platform(s), create agent-team.yaml, register with relay |
| `teamrc join <invite>` | Join team, write agent-team.yaml, apply to platform(s) |
| `teamrc apply` | Apply agent-team.yaml to platform (offline) |
| `teamrc diff` | Compare local vs relay state |
| `teamrc status` | Show config, sync state, team info |
| `teamrc sync` | Manual one-shot sync |
| `teamrc daemon` | Start background sync daemon |

All commands that need a platform support `--platform <name>` to override auto-detection. When multiple platforms are detected and no override is given, the CLI prompts with an option to configure both.

### 8.2 Daemon

Long-lived Node.js background process:

- Watches files via chokidar (`agent-team.yaml`, platform-specific paths from `adapter.watchPaths()`)
- On local file change: immediate push to relay
- On poll interval (2 minutes): check relay for remote changes via lightweight `GET /api/sync/check`
- On remote `agent-team.yaml` change: regenerates platform-native agent files automatically
- Self-trigger prevention: caches hashes of files written from remote changes
- Graceful reconnection on relay failure

### 8.3 Relay

Elixir/Phoenix application.

**API Endpoints:**

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| POST | `/api/join` | Signed | Join team by invite code |
| POST | `/api/teams` | Signed | Create a team |
| GET | `/api/teams/:token` | Signed | Get team definition |
| POST | `/api/sync` | Signed | Full sync (send hashes + files, receive changes) |
| GET | `/api/sync/check` | Signed | Lightweight poll (changed since timestamp?) |
| POST | `/api/push` | Signed | Push a single entry |
| GET | `/api/pull` | Signed | Pull entries for a platform |

**Web UI:**
- `GET /` — LiveView team creation interface with templates

**Storage:**
- **Postgres** (persistent): teams, members (with soul field), invites
- **GenServer** (in-memory): file hashes per platform, file content with 24h TTL, token-to-team mapping, per-team last_updated_at timestamps

### 8.4 Platform Adapters

Each adapter implements:

```typescript
interface PlatformAdapter {
  readTeam(): TeamDefinition | null;
  writeTeam(team: TeamDefinition, scope?: TeamScope): void;
  readKnowledge(): string;
  writeKnowledge(content: string): void;
  appendKnowledge(entries: string[]): void;
  getHashes(): Record<string, string>;
  watchPaths(): string[];
  writeFile(key: string, content: string): void;
  readFile(key: string): string | null;
  installHooks(relay: string, token: string): void;
}
```

| Platform | Canonical Source | Native Format | Knowledge File | Scope Options |
|----------|-----------------|---------------|----------------|---------------|
| Claude Code | `agent-team.yaml` | `.claude/agents/tb-*.md` (YAML frontmatter + markdown) | `.claude/team-knowledge.md` | project / global |
| OpenClaw | `agent-team.yaml` | `~/.openclaw/workspace/agents/` | `~/.openclaw/workspace/TEAM-KNOWLEDGE.md` | global only |

**Claude Code native format:** Each agent becomes a subagent markdown file with YAML frontmatter:

```markdown
---
name: architect
description: "Design system architecture on the fraudstory team."
model: inherit
---

# Team: fraudstory

You are architect, a Design system architecture on the fraudstory team.
```

**CLAUDE.md integration:** teamrc appends a section to CLAUDE.md listing team members and instructing the agent to read/write `.claude/team-knowledge.md`.

## 9. Sync Mechanics

### 9.1 What Syncs

| Data Type | Strategy | Reason |
|-----------|----------|--------|
| Agent definitions (`agent-team.yaml`) | Last-write-wins (timestamp) | Rare edits, simple resolution |
| Team knowledge | Append-only merge | Entries are independent, both sides valid |
| Task state (future) | State machine | Forward-only transitions |
| Task comments (future) | Append-only merge | Both entries valid |

### 9.2 Sync Flow

```
daemon detects file change (chokidar)
  |
  +-- Compute hashes of watched files
  +-- POST /api/sync { token, platform, hashes, files }
  |     Relay stores hashes + content
  |     Returns files where other platforms have different hashes
  |     Each change includes { content, updated_at }
  |
  +-- Apply changes via conflict resolution
  |     Knowledge files: append-only merge (dedup by content hash)
  |     Definition files: last-write-wins (compare timestamps)
  |
  +-- If agent-team.yaml changed: regenerate platform-native agent files
  |
  +-- Update local hash cache (prevent self-trigger)
```

### 9.3 Polling Flow

```
every 2 minutes:
  GET /api/sync/check?token=X&since=T
    -> { changed: false }  // nothing to do
    -> { changed: true }   // do full sync
```

### 9.4 Offline Handling

- Content is stored in relay memory with 24-hour TTL
- If a machine is offline, changes wait in the relay buffer
- When the machine comes back, next poll picks up all changes
- If relay restarts, machines re-sync on next poll (send full state)

## 10. Authentication & Security

### 10.1 Keypair Model

- Each machine generates an Ed25519 keypair on first use
- Private key stored at `~/.teamrc/key` (mode 0o600, directory mode 0o700)
- Public key derived token: `trc_ak_<base64url(public_key)>`
- All API requests signed with private key

### 10.2 Signature Verification

- POST: sign raw JSON body, include signature as `x-tb-signature` header
- GET: sign `"GET /path?query"`, include signature as `x-tb-signature` header
- `x-tb-timestamp` header required, must be within 5 minutes of server time (replay protection)
- Timestamp included in signed message (`{timestamp}.{body}`)
- BOLA prevention: token in request must correspond to the public key that produced the signature

### 10.3 Invite Codes

- Created via web UI, `trc_inv_` prefix
- Multi-use: multiple machines can join with the same code
- 24-hour expiry
- `POST /api/join` requires signature (authenticated)

### 10.4 Security Hardening

- **Rate limiting**: Token bucket per token (60 req/min for check, 10 req/min for sync)
- **Input validation**: File paths (no traversal, no absolute paths), platform names (alphanumeric), hashes (max 128 chars), max 100 files per sync
- **Content size limits**: 256KB per file
- **CORS**: Restrictive by default, configurable allowlist
- **Error responses**: Generic errors only, no stack traces or internal details
- **Production guard**: `skip_auth` config ignored in production builds

## 11. Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Relay runtime | Elixir/Phoenix | Concurrency, LiveView for web UI, built-in PubSub |
| CLI runtime | Node.js | npx distribution, same ecosystem as target users |
| Persistent storage | Postgres (Ecto) | Teams, members, invites |
| Sync data storage | GenServer (in-memory) | Fast, auto-cleaned, loss triggers re-sync |
| Auth | Ed25519 keypairs | No signup, cryptographic identity, replay protection |
| Sync mechanism | HTTP polling (2-min) | Stateless, scales to millions behind load balancer |
| Team spec format | YAML | Human-editable, version-controllable |
| File watching | chokidar | Reliable cross-platform filesystem events |
| Conflict resolution | Strategy per data type | Append-only for knowledge, LWW for definitions |
| Distribution | npm (npx) | Zero install for Node.js users |

### Why not WebSockets?

At 5M users, persistent WebSocket connections would require ~40-80GB RAM for connection state alone. HTTP polling at 2-minute intervals = ~42K req/s, easily handled by a few nodes behind a load balancer. The trade-off (2-min max latency) is acceptable for files that change a few times a day.

## 12. Installation

**CLI (on each machine):**

```bash
npx teamrc                     # Run directly (no install)
npm install -g teamrc          # Install globally from npm
npm install -g ./teamrc-0.1.0.tgz  # Install from tarball (no git/registry needed)
```

**Relay (self-hosted):**

```bash
cd relay && mix phx.server
```

Requires: Elixir 1.18+, Postgres. Binds to `0.0.0.0` in dev by default. For cross-machine access, ensure firewall allows port 4000 or use SSH tunneling:

```bash
ssh -L 4000:localhost:4000 user@relay-host
```

## 13. Success Criteria

- A developer can create a team via web UI and join from CLI in under 5 minutes
- Teams stay in sync without manual intervention after initial setup
- Multiple platforms on the same machine are detected and configurable together
- Adding a new platform = writing one adapter module
- The relay can be self-hosted with `mix phx.server` + Postgres
- Team definitions persist across relay restarts

## 14. Future Enhancements

- npm publish of CLI package
- Auto-start daemon after `join`/`init`
- End-to-end encryption (encrypt content with team-shared key)
- Platform adapters: Cursor, Windsurf, CrewAI, AutoGen, LangGraph
- Task coordination system (structured tasks for agents)
- MCP server for mid-session reads (`teamrc:read-knowledge`, `teamrc:list-teammates`)
- Web dashboard for team management
- SOUL.md editing in web UI
- Agent memory synchronization
- Permissions and identity (agent credentials and capabilities)
- Plugin architecture for more platforms
- Daemon as system service (launchd / systemd)

## 15. Open Questions

1. How do we handle platforms that restructure their agent config format between versions?
2. Should conflict warnings be surfaced to the user via a notification mechanism?
3. How should task coordination work? (State machine transitions, assignment, comments)
4. Should the daemon auto-start after `join`/`init`, or require manual `teamrc daemon`?
