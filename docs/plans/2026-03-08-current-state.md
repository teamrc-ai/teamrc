# teamrc — Current State

**Date:** 2026-03-08

---

## Working Happy Flows

### CLI Commands

| Command | Status | Description |
|---------|--------|-------------|
| `teamrc init` | Working | Create team from scratch. Generates `agent-team.yaml`, writes agent files for detected platforms, pushes to relay. |
| `teamrc join <invite>` | Working | Join existing team. Downloads definition from relay, writes agent files, starts syncing. |
| `teamrc sync` | Working | Bidirectional sync — push local changes to relay, pull remote changes. Syncs agents, rules, skills, knowledge. |
| `teamrc apply` | Working | Write `agent-team.yaml` to local platform files. Pure local, no relay. |
| `teamrc export` | Working | Export relay team to `agent-team.yaml`. |
| `teamrc diff` | Working | Show differences between local YAML and relay. |
| `teamrc status` | Working | Show current team info, connected platforms, sync state. |
| `teamrc daemon` | Working | Watch for file changes, auto-sync knowledge to relay in background. |
| `teamrc push` | Working | Push a knowledge/memory entry to relay for cross-platform distribution. |
| `teamrc delete` | Working | Remove local team artifacts, optionally delete from relay. |
| `teamrc login` | Working | Device auth flow to link Clerk account. Opens browser, polls for verification. |
| `teamrc log` | Working | View sync history with attribution (who pushed what). |

### Platform Adapters

| Platform | Agents | Rules | Skills | Knowledge | Scope |
|----------|--------|-------|--------|-----------|-------|
| Claude Code | `.claude/agents/trc-*.md` | `.claude/rules/` | `.claude/skills/` | `CLAUDE.md` team section | Project |
| Cursor | `.cursor/agents/trc-*.md` | `.cursor/rules/trc-*.mdc` | `.cursor/skills/trc-*/` | `CURSOR.md` | Project |
| Codex | `.codex/agents/trc-*.toml` + `AGENTS.md` | `.codex/config.toml` | — | `AGENTS.md` | Project |
| OpenClaw | `~/.openclaw/workspaces/trc-*/` | `SOUL.md` per workspace | — | — | Global only |
| Gemini | `GEMINI.md` (flattened) | — | — | — | Project (limited) |

### Relay (Elixir/Phoenix)

| Feature | Status |
|---------|--------|
| Team CRUD via signed API | Working |
| Invite codes (24h TTL, 144-bit entropy, multi-use) | Working |
| Push/pull memory with cross-platform delivery | Working |
| Self-filtering (don't echo own entries) | Working |
| Sync with hash-based change detection | Working |
| Rate limiting (per-IP + per-token, ETS) | Working |
| Ed25519 signature verification with replay protection | Working |
| Replay protection (timestamp in signed message, 5-min window) | Working |
| BOLA check (verified token must match request token) | Working |
| Content caps (50MB/team, 50 rules, 50 skills, 10KB each) | Working |

### Web UI

| Page | Route | Status |
|------|-------|--------|
| Landing/redirect | `/` | Working — redirects to `/new` or `/dashboard` based on auth |
| Team creation wizard | `/new` | Working — template picker, member/rule/skill editor, invite code output |
| Dashboard | `/dashboard` | Working — requires Clerk auth. Shows machines (with revocation) and teams (with participants) |
| Device auth verification | `/auth/verify` | Working — consent screen for `teamrc login` |
| Sign out | `/auth/sign-out` | Working |

### Auth

| Feature | Status |
|---------|--------|
| Ed25519 keypair generation (`~/.teamrc/key`) | Working |
| Signed requests (timestamp + body/path) | Working |
| Optional Clerk account linking via device auth | Working |
| Machine revocation from dashboard | Working |
| Account reassociation | Working |
| Directory permissions (`0o700` on `~/.teamrc/`) | Working |
| `skip_auth` compile-time guard (test/dev only) | Working |

### Security (Audited)

All 33 items from `docs/security-audit.md` addressed — 28 fixed, 3 noted as low-risk, 2 by-design.

---

## Not Working / Not Yet Built

### Multi-Project Teams (Planned)
**Plan:** `docs/plans/2026-03-07-multi-project-teams.md`

Currently teamrc supports one team per machine (global `~/.teamrc/config.json` holds a single `teamId`). The plan covers:

- **Config split**: Global config = machine identity. Project config = team identity in `agent-team.yaml`.
- **Relay multi-team**: `token_teams` already supports many-to-many, GenServer needs `token => [team_ids]`.
- **Per-project teams**: Different projects on the same machine can have different teams.
- **Global team fallback**: Optional global team in `~/.teamrc/config.json` for users who want one team everywhere.

### New Platform Adapters (Planned)

| Platform | Priority | Agent Support | Notes |
|----------|----------|---------------|-------|
| GitHub Copilot | HIGH | `.github/agents/*.agent.md` | Named agents, instructions, tools |
| Amazon Q | HIGH | `.amazonq/cli-agents/*.json` | Named agents, tools |
| Windsurf | MEDIUM | Rules only (`.windsurf/rules/*.md`) | No named agents |
| Cline | MEDIUM | Rules only (`.clinerules`) | No named agents |
| JetBrains Junie | MEDIUM | Rules only (`.junie/guidelines.md`) | No named agents |
| Continue.dev | LOW | Rules only (`.continue/config.yaml`) | No named agents |
| Aider | LOW | Rules only (`CONVENTIONS.md`) | No named agents |

### Gemini Adapter Rewrite (Planned)
Currently flattens all agents into a single `GEMINI.md`. Needs rewrite to use native `.gemini/agents/*.md` files (mirrors Claude Code adapter pattern).

### CLI UX Overhaul (Planned)
- No colors, no spinners, raw readline prompts
- Plan calls for `@clack/prompts` (select, multiselect, spinner, structured output)
- Platform detection needs expansion from 5 to 12 platforms

### Web UI Enhancements (Planned)
- Team detail page (view/edit members, rules, skills, generate new invites)
- Dashboard: show team-to-machine-to-project relationships for multi-team
- Wizard: platform selection step, global vs project scope toggle

---

## Test Coverage

| Suite | Count | Command |
|-------|-------|---------|
| CLI (TypeScript) | 67 tests | `cd cli && npm test` |
| Relay (Elixir) | 114 tests | `cd teamrc && mix test` |
| E2E | 9 scenarios | `test/e2e.sh` (relay API with curl) |

---

## Key Files

```
cli/
  src/index.ts              — CLI entry point (all commands)
  src/auth.ts               — Ed25519 keypair management
  src/client.ts             — API client with signed requests
  src/config.ts             — ~/.teamrc/config.json management
  src/team-yaml.ts          — agent-team.yaml read/write
  src/daemon.ts             — File watcher + auto-sync
  src/resolve-rules.ts      — Per-agent rule/skill resolution
  src/adapters/
    base.ts                 — Shared types + utilities
    claude-code.ts          — Claude Code adapter
    cursor.ts               — Cursor adapter
    codex.ts                — Codex adapter
    openclaw.ts             — OpenClaw adapter
    gemini.ts               — Gemini adapter (needs rewrite)

teamrc/
  lib/teamrc/
    teams.ex                — GenServer for team state + sync
    accounts.ex             — Accounts context
    device_auth.ex          — Device auth GenServer
  lib/teamrc_web/
    live/team_live.ex       — Team creation wizard
    live/dashboard_live.ex  — Dashboard (machines + teams)
    live/auth_verify_live.ex — Device auth consent
    controllers/
      api_controller.ex     — Team API endpoints
      auth_controller.ex    — Device auth endpoints
      account_controller.ex — Account management
    plugs/
      verify_signature.ex   — Ed25519 signature verification
      verify_clerk_jwt.ex   — Clerk JWT verification
      rate_limiter.ex       — Per-IP + per-token rate limiting
      cors.ex               — CORS headers

docs/
  security-audit.md         — Full security audit (33 items)
  plans/                    — Implementation plans
scripts/
  uninstall.sh              — Remove all teamrc artifacts
test/
  e2e.sh                    — End-to-end API tests
```
