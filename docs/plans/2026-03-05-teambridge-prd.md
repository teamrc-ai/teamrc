# TeamBridge PRD

**Product Requirements Document**
**Date:** 2026-03-05
**Status:** Draft

---

## 1. Problem

Developers running multi-agent teams across platforms (Claude Code, OpenClaw, Claude Desktop) face:

- **Configuration drift** — teams defined on one platform don't match the other. Roles, personas, and constraints diverge silently.
- **No shared memory** — an agent on Claude Code learns something; the agent on OpenClaw has no idea.
- **Manual duplication** — setting up the same team on a new platform means recreating every agent from scratch.
- **Cross-machine isolation** — platforms run on different machines with no shared filesystem.

The result: agents duplicate work, contradict each other, lose context, and teams can't be moved between platforms.

## 2. Solution

TeamBridge is a stateless relay that keeps multi-agent teams in sync across platforms.

- **No signup** — identity is a locally-generated crypto keypair
- **No data storage** — each platform is its own source of truth; the relay is a pass-through
- **No background processes** — sync runs via platform hooks on session start
- **Automatic** — after one-time setup, sync happens without user intervention

## 3. Users

- Developers running multi-agent teams across 2+ platforms
- Primary platforms: Claude Code, OpenClaw, Claude Desktop
- Technically proficient (comfortable with CLI, config files, npm)

## 4. User Experience

### 4.1 First Machine (has existing team)

```bash
npx teambridge init
```

Output:

```
Detected platform: claude-code
Generated keypair.
Found team "my-project" (3 agents: architect, implementer, reviewer)
Added SessionStart hook to ~/.claude/settings.json
Registered with relay.

To connect another machine:
  npx teambridge join tb_ak_7f3a9c2b...
```

What `init` does:
1. Detects which platform is installed locally
2. Generates a crypto keypair, saves to `~/.teambridge/key`
3. Reads the existing team definition from the platform's native files
4. Pushes it to the relay (buffered, not stored)
5. Adds a `SessionStart` hook to the platform config that runs `npx teambridge sync`
6. Adds a `PostToolUse` / post-response hook that runs `npx teambridge push` on memory writes

### 4.2 Additional Machines

```bash
npx teambridge join tb_ak_7f3a9c2b...
```

Output:

```
Detected platform: openclaw
Connecting to relay...
Found team "my-project" from Claude Code:
  - architect: "Focus on system design and API contracts"
  - implementer: "Write clean, tested code"
  - reviewer: "Review PRs for correctness and security"

Scaffolding OpenClaw agents...
  Created ~/.openclaw/agents/architect/ with SOUL.md
  Created ~/.openclaw/agents/implementer/ with SOUL.md
  Created ~/.openclaw/agents/reviewer/ with SOUL.md
  Updated ~/.openclaw/config.yaml with agent routing
  Added bootstrap hook for automatic sync
  Added MCP server config for mid-session reads

Done. Sync is automatic from now on.
```

What `join` does:
1. Detects which platform is installed locally
2. Connects to relay using the provided team token
3. Pulls the full team definition
4. Translates to the local platform's format
5. Scaffolds all agents locally (creates directories, writes config files, persona files)
6. Adds sync hooks to the platform config
7. Optionally adds MCP server config for mid-session memory reads

### 4.3 Ongoing Use (automatic, invisible)

Every time an agent session starts on any platform:
1. The `SessionStart` / bootstrap hook runs `npx teambridge sync`
2. `sync` reads local state, sends hashes to relay, receives changes
3. Creates/updates local files as needed (new agents, updated roles, new memory entries)
4. Pushes local changes to relay for other platforms to pick up

The user does nothing. Sync is invisible.

### 4.4 Mid-Session Memory (optional MCP)

For agents that want to read shared memory during a session (not just at startup), the relay exposes a lightweight MCP server:

- `teambridge:read-memory` — query shared memory by topic
- `teambridge:list-teammates` — see team members across platforms
- `teambridge:get-role` — get a specific role's definition

These are read-only. All writes go through the CLI hooks to ensure reliable file operations.

## 5. Architecture

```
Machine A (Claude Code)              Machine B (OpenClaw)
+-----------------------+           +-----------------------+
| SessionStart hook:    |           | Bootstrap hook:       |
|   npx teambridge sync |           |   npx teambridge sync |
|                       |           |                       |
| PostToolUse hook:     |           | Post-response hook:   |
|   npx teambridge push |           |   npx teambridge push |
|                       |           |                       |
| MCP (optional):       |           | MCP (optional):       |
|   teambridge:read-*   |           |   teambridge:read-*   |
+-----------+-----------+           +-----------+-----------+
            |                                   |
            |           HTTPS                   |
            +-----------+-----------------------+
                        |
               +--------v--------+
               |  Relay          |
               |  (stateless)    |
               |                 |
               |  In-memory      |
               |  write buffer   |
               |  Hash index     |
               |  Auth verify    |
               |                 |
               |  No database.   |
               |  No persistence.|
               +-----------------+
```

### 5.1 CLI (`npx teambridge`)

The core of the product. A Node.js CLI that:

- **`init`** — detect platform, generate keypair, register team, add hooks
- **`join <token>`** — connect to existing team, scaffold agents locally, add hooks
- **`sync`** — bidirectional sync: pull remote changes, push local changes
- **`push`** — push specific local changes (memory writes) to relay
- **`serve`** — run the relay server (for self-hosting)
- **`status`** — show current sync state, connected platforms, team members

### 5.2 Relay Server

A stateless HTTP server (Node.js). Endpoints:

- `POST /sync` — receive local state hashes, return changes from other platforms
- `POST /push` — receive a change (memory entry, config update), buffer it
- `GET /pull` — get buffered changes for a specific platform
- `GET /mcp` — Streamable HTTP MCP endpoint for mid-session reads
- `POST /register` — register a new platform connection

State held in memory only:
- **Write buffer** — pending changes keyed by team token, with TTL
- **Hash index** — last-known hashes per platform per team, for conflict detection
- **Connection registry** — which platforms are connected to which team

If the relay restarts, all in-memory state is lost. Next `sync` from any platform does a full reconciliation.

### 5.3 Platform Adapters

Each platform has an adapter that knows:
- Where team config files live
- Where memory files live
- Where agent/role definitions live
- How to scaffold a new agent (create dirs, write files, register)
- How to read/write the platform's native formats

Initial adapters:

| Platform | Team config | Memory | Agent scaffold |
|---|---|---|---|
| Claude Code | `~/.claude/teams/{name}/config.json`, `CLAUDE.md` | Memory files in project | Write `config.json`, update `CLAUDE.md` |
| OpenClaw | `~/.openclaw/config.yaml` | `MEMORY.md` in workspace | `openclaw agents add`, write `SOUL.md`/`AGENTS.md` |
| Claude Desktop | `claude_desktop_config.json` | Project instructions | Update project config |

Adding a new platform = writing a new adapter module.

## 6. Sync Mechanics

### 6.1 What Syncs

| Data type | Direction | Mechanism |
|---|---|---|
| Team members & roles | Bidirectional | `sync` on session start |
| Agent personas/constraints | Bidirectional | `sync` on session start |
| Shared memory | Bidirectional | `push` on write, `sync` on session start |
| Tasks | Bidirectional | `sync` on session start |

### 6.2 Sync Flow

```
npx teambridge sync --platform claude-code
  |
  +-- Read local state
  |     Parse team config, memory files, role definitions
  |     Compute content hashes
  |
  +-- POST /sync to relay
  |     Send: { platform, team_token, hashes: { file: hash, ... } }
  |     Receive: { changes: [...], conflicts: [...] }
  |
  +-- Apply non-conflicting changes
  |     Create new agent dirs if needed
  |     Write/update config files, persona files, memory
  |     Platform adapter handles format translation
  |
  +-- Handle conflicts
  |     Write both versions to a conflict file
  |     Inject context into session: "Conflict detected, resolve..."
  |     Agent merges on next interaction
  |
  +-- Push local changes
        Send new/updated content to relay buffer
```

### 6.3 Conflict Detection

The relay tracks hashes per platform per file. A conflict occurs when:
- Platform A changed file X since last sync
- Platform B also changed file X since last sync

Resolution: both versions are presented to the agent (injected via SessionStart hook stdout). The agent (an LLM) reads both and produces a merged version.

### 6.4 Offline Handling

If a platform is offline when changes are pushed:
- Changes sit in the relay's in-memory buffer (TTL: configurable, default 24h on paid, 1h on free)
- When the platform comes back and runs `sync`, it picks up buffered changes
- If buffer expired (relay restarted or TTL hit), the syncing platform sends its full state; the other platform does a full reconciliation on its next sync

## 7. Authentication

### 7.1 Keypair Model

- `teambridge init` generates an Ed25519 keypair
- Private key stored at `~/.teambridge/key` (never leaves the machine)
- Public key derived team token: `tb_ak_<base58(public_key)>`
- All API requests signed with private key; relay verifies with public key

### 7.2 Team Membership

- The `init` machine creates the team and is the implicit owner
- `join <token>` adds a platform to an existing team
- The team token IS the public key — anyone with it can join
- For access revocation: generate a new keypair (`teambridge rotate`), re-join other machines

### 7.3 No Accounts

- No email, no password, no OAuth
- No server-side user records
- Identity = keypair, membership = shared token

## 8. Self-Hosting

```bash
npx teambridge serve
# or
docker run -p 3000:3000 teambridge/relay
```

Point your machines at your own relay:

```bash
npx teambridge init --relay https://my-server:3000
npx teambridge join tb_ak_7f3a9c2b... --relay https://my-server:3000
```

Same codebase. Same npm package. Zero configuration for the relay (no database, no env vars required).

## 9. Hosted Service

### 9.1 URL

`relay.teambridge.app`

### 9.2 Pricing

| | Free | Pro |
|---|---|---|
| Platforms connected | 2 | Unlimited |
| Buffer retention | 1 hour | 24 hours |
| Teams | 1 | Unlimited |
| Sync | Session start only | Session start + push hooks |
| Self-host | Always available | Always available |

Pricing TBD. Launch free with generous limits. Add paid tier based on usage patterns.

## 10. Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Runtime | Node.js | Shared with npx distribution, same ecosystem as target users |
| Relay storage | In-memory only | Stateless relay principle; no data persistence |
| Auth | Ed25519 keypairs | No signup, no accounts, cryptographic identity |
| Sync trigger | Platform hooks | No daemon, no background process, automatic |
| Mid-session reads | MCP (Streamable HTTP) | Native integration with Claude Code + OpenClaw |
| File operations | CLI (not MCP) | MCP can't write files reliably; CLI can |
| Conflict resolution | Agent-driven | LLMs can read both versions and merge intelligently |
| Distribution | npm (npx) | Zero install for Node.js users |
| Self-hosting | Same package | `npx teambridge serve` runs the relay |

## 11. Non-Goals (v1)

- Real-time sync (event-driven is sufficient)
- Web dashboard for team configuration (CLI-first)
- Support for non-agent platforms
- Persistent storage or backup
- Multi-tenancy or workspace isolation on the relay
- End-to-end encryption (TLS in transit is sufficient for v1)

## 12. Future Considerations

- Web dashboard for visual team configuration
- End-to-end encryption (encrypt buffer contents with team-shared key)
- Platform adapters: Cursor, Windsurf, CrewAI, AutoGen, LangGraph
- Diff-based memory sync (optimize for large memory files)
- Real-time push via WebSocket (optional daemon mode)
- Team roles and permissions (read-only members, admin)

## 13. Success Criteria

- A developer can connect Claude Code and OpenClaw teams in under 5 minutes
- Teams stay in sync without manual intervention after initial setup
- Adding a new platform takes writing one adapter module
- The relay can be self-hosted with a single command
- Zero data is persisted on the relay server

## 14. Open Questions

1. Should the team token be the raw public key, or a shorter derived identifier?
2. How do we handle platforms that restructure their agent config format between versions?
3. Should the free tier buffer retention be 1 hour or longer?
4. Do we need a `teambridge diff` command to preview changes before applying?
5. How do we handle large teams (10+ agents) — does scaffolding become slow?
6. Should conflict files be auto-cleaned after resolution, or left for audit?
