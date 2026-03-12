# teamrc — Current State

**Date:** 2026-03-09

---

## Working Happy Flows

### CLI Commands

| Command | Status | Description |
|---------|--------|-------------|
| `teamrc init` | Working | Create team from template catalog or custom. Generates `.teamrc.yaml`, writes agent files for detected platforms, pushes to relay. Supports `--team <id>` for template selection, `--global` flag. |
| `teamrc join <invite>` | Working | Join existing team. Downloads definition from relay, writes agent files, merges knowledge (append-only dedup). |
| `teamrc sync` | Working | Bidirectional sync — push local changes to relay, pull remote changes. Syncs agents, skills, knowledge. |
| `teamrc apply` | Working | Write `.teamrc.yaml` to local platform files. Pure local, no relay. Supports `--scope` and `--platform` filters. |
| `teamrc import <platform>` | Working | Import team from platform-native files into `.teamrc.yaml`. |
| `teamrc export` | Working | Export relay team to `.teamrc.yaml`. |
| `teamrc diff` | Working | Show differences between local YAML and relay (added/removed/changed agents, name). |
| `teamrc status` | Working | Show machine identity, token, relay connection, local team, remote team members. |
| `teamrc daemon` | Working | Background sync daemon with configurable poll interval (default 120s, min 5s). |
| `teamrc push` | Working | Push team definition and knowledge to relay. |
| `teamrc pull` | Working | Pull from relay, merge knowledge, apply to platforms, update `.teamrc.yaml`. |
| `teamrc delete` | Working | Remove local team artifacts with confirmation (type team name). Uninstalls from all platforms, deletes `~/.teamrc/` and `.teamrc.yaml`. |
| `teamrc login` | Working | Device auth flow to link Clerk account. Opens browser, polls for verification. |
| `teamrc clone <invite>` | Working | Clone team locally from invite WITHOUT joining (no relay relationship). |
| `teamrc invite` | Working | Create time-limited invite code (default 24h). |
| `teamrc whoami` | Working | Show current identity: token, machine name, linked account, teamId, relay, platforms. |
| `teamrc doctor` | Working | Health check: keypair, config, relay reachability, `.teamrc.yaml` parse, platform agent count, account link. |

### Template Catalog

| Feature | Status |
|---------|--------|
| Template directory structure (`templates/{agents,skills,teams}/`) | Working |
| Agent catalog (~68 agents across 10 categories) | Working |
| Skill catalog (~49 skills across 8+ categories) | Working |
| Team templates (12 teams: fullstack, backend, frontend, security, mobile, data-ml, marketing, research, devops, documentation, startup-mvp, custom) | Working |
| Catalog loader — TypeScript (`cli/src/catalog.ts`) | Working |
| Catalog loader — Elixir (`teamrc/lib/teamrc/catalog.ex`) | Working |
| `_index.yaml` ordering + category grouping | Working |
| Per-agent skill assignment via `agentSkills` in team templates | Working |
| Unified Rule+Skill model (rules are skills with `alwaysApply: true`) | Working |

### Platform Adapters

| Platform | Agents | Skills (alwaysApply → rules) | Skills (on-demand) | Per-agent Skills | Knowledge | Scope |
|----------|--------|-----|--------|-----------|-------|-------|
| Claude Code | `.claude/agents/trc-*.md` | `.claude/rules/trc-*.md` | `.claude/skills/trc-*/SKILL.md` | Native `skills` frontmatter | `CLAUDE.md` team section | Project + Global |
| Cursor | `.cursor/agents/trc-*.md` | `.cursor/rules/trc-*.mdc` | `.cursor/skills/trc-*/SKILL.md` | Inlined in agent body | — | Project + Global |
| Codex | `.codex/agents/trc-*.toml` + `AGENTS.md` | Section in `AGENTS.md` | `.agents/skills/trc-*/SKILL.md` | Inlined in `developer_instructions` | `AGENTS.md` | Project + Global |
| Gemini | `.gemini/agents/trc-*.md` | Section in `GEMINI.md` | `.agents/skills/trc-*/SKILL.md` | Inlined in agent body | `GEMINI.md` marker block | Project + Global |
| OpenClaw | `.agents/agents/trc-*.md` | In agent body | `.agents/skills/trc-*/SKILL.md` | Native `skills` frontmatter | `AGENTS.md` | Project + Global |

### Relay (Elixir/Phoenix)

| Feature | Status |
|---------|--------|
| Team CRUD via signed API | Working |
| Multi-team per token (token → team_ids via token_teams table) | Working |
| Invite codes (24h TTL, 144-bit entropy, multi-use) | Working |
| Push/pull with cross-platform delivery | Working |
| Self-filtering (don't echo own entries) | Working |
| Sync with hash-based change detection | Working |
| Rate limiting (per-IP + per-token, ETS) | Working |
| Ed25519 signature verification with replay protection | Working |
| Replay protection (timestamp in signed message, 5-min window) | Working |
| BOLA check (verified token must match request token) | Working |
| Content caps (50MB/team, 50 members, 50 skills, 10KB skill body) | Working |
| `team_id` param routing (multi-project) | Working |

### Web UI

| Page | Route | Status |
|------|-------|--------|
| Landing/redirect | `/` | Working — redirects to `/new` or `/dashboard` based on auth |
| Team creation wizard | `/new` | Working — catalog-based template picker, one-click team creation |
| Team dashboard | `/teams/:id` | Working — view/edit members, skills, invites, machines, participants |
| Member detail | `/teams/:team_id/members/:member_id` | Working — edit name, role, soul (instructions), assign skills, delete member |
| Guide / onboarding | `/guide` | Working — overview, members, skills, instructions, knowledge, syncing, `.teamrc.yaml` format |
| Invite redirect | `/invite/:code` | Working — validates invite, redirects to team dashboard |
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

All 33 items from `docs/security-audit.md` addressed — 28 fixed, 3 noted as low-risk, 2 by-design. Additional hardening: input validation, size limits, crash safety, IDOR protection on member/skill operations.

---

## Not Working / Not Yet Built

### New Platform Adapters (Planned)

| Platform | Priority | Agent Support | Notes |
|----------|----------|---------------|-------|
| GitHub Copilot | HIGH | `.github/agents/*.agent.md` | Named agents, instructions, tools. Stub adapter exists. |
| Amazon Q | HIGH | `.amazonq/cli-agents/*.json` | Named agents, tools. Stub adapter exists. |
| Windsurf | MEDIUM | Rules only (`.windsurf/rules/*.md`) | No named agents. Stub adapter exists. |
| Cline | MEDIUM | Rules only (`.clinerules`) | No named agents. Stub adapter exists. |
| JetBrains Junie | MEDIUM | Rules only (`.junie/guidelines.md`) | No named agents |
| Continue.dev | LOW | Rules only (`.continue/config.yaml`) | No named agents |
| Aider | LOW | Rules only (`CONVENTIONS.md`) | No named agents |

### Multi-Project — Remaining Work

The core multi-project infrastructure is built (config split, `team_id` routing, `.teamrc.yaml` project scoping). Remaining:
- Global team mode (`--global` flag + `globalTeam` in config) — partially implemented
- OpenClaw team-namespaced workspaces for multi-project collision avoidance
- Dashboard: show team-to-machine-to-project relationships for multi-team
- `teamrc teams` command to list all teams on machine

### Web UI Enhancements (Planned)

- Dashboard restructure for multi-team view (machine-project-team relationships)
- Landing page (low priority — CLI is primary entry point)

---

## Test Coverage

| Suite | Count | Command |
|-------|-------|---------|
| CLI (TypeScript) | 185 tests | `cd cli && npm test` |
| Relay (Elixir) | 148 tests | `cd teamrc && mix test` |
| E2E | 9 scenarios | `test/e2e.sh` (relay API with curl) |

---

## Key Files

```
templates/
  agents/                     — ~68 reusable agent definitions (YAML)
  skills/                     — ~49 skill definitions (YAML, includes what were "rules")
  teams/                      — 12 team compositions (YAML)

cli/
  src/index.ts                — CLI entry point (17 commands)
  src/auth.ts                 — Ed25519 keypair management
  src/client.ts               — API client with signed requests (TeamrcClient)
  src/config.ts               — ~/.teamrc/config.json management, platform detection
  src/catalog.ts              — Template catalog loader (agents, skills, teams)
  src/team-yaml.ts            — .teamrc.yaml read/write/validation
  src/daemon.ts               — Background sync daemon
  src/adapters/
    base.ts                   — Shared types (Skill, TeamMember, TeamDefinition), utilities
    claude-code.ts            — Claude Code adapter (agents, rules, skills, knowledge)
    cursor.ts                 — Cursor adapter (agents, rules, skills)
    codex.ts                  — Codex adapter (agents, AGENTS.md, skills)
    gemini.ts                 — Gemini adapter (native agent files, GEMINI.md)
    openclaw.ts               — OpenClaw/OpenHands adapter (.agents/agents/, skills)

teamrc/
  lib/teamrc/
    teams.ex                  — Team context module (multi-team per token, queries Postgres directly)
    accounts.ex               — Accounts context
    device_auth.ex            — Device auth GenServer
    catalog.ex                — Template catalog loader (Elixir side)
  lib/teamrc_web/
    live/team_live.ex         — Team creation wizard (catalog template picker)
    live/team_detail_live.ex  — Team dashboard (members, skills, invites, machines)
    live/member_detail_live.ex — Member detail (edit soul, assign skills)
    live/guide_live.ex        — Guide / onboarding page
    live/invite_live.ex       — Invite code validation + redirect
    live/dashboard_live.ex    — Dashboard (machines + teams, Clerk auth)
    live/auth_verify_live.ex  — Device auth consent
    controllers/
      api_controller.ex       — Team API endpoints (with team_id routing)
      auth_controller.ex      — Device auth endpoints
      account_controller.ex   — Account management
    plugs/
      verify_signature.ex     — Ed25519 signature verification
      verify_clerk_jwt.ex     — Clerk JWT verification
      rate_limiter.ex         — Per-IP + per-token rate limiting
      cors.ex                 — CORS headers

docs/
  security-audit.md           — Full security audit (33 items, all addressed)
  plans/                      — Implementation plans
scripts/
  uninstall.sh                — Remove all teamrc artifacts
test/
  e2e.sh                      — End-to-end API tests
```
