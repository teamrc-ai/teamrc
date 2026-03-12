# TeamBridge v1 Implementation Plan

**Status:** MVP Complete
**Date:** 2026-03-05
**Last Updated:** 2026-03-05

---

## Summary

All MVP tasks are complete. 108 tests passing (38 CLI + 70 relay). The system implements the full v0.4 PRD. Post-MVP fixes include multi-platform detection, daemon agent file regeneration, and team knowledge integration.

---

## Architecture

```
teambridge/
  relay/                        # Elixir Phoenix app
    lib/
      teambridge/
        teams.ex                # GenServer — sync state + team management
        auth.ex                 # Ed25519 signature verification
        repo.ex                 # Ecto Repo
        schema/
          team.ex               # Ecto schema
          member.ex             # Ecto schema (with soul field)
          invite.ex             # Ecto schema (multi-use, 24h expiry)
      teambridge_web/
        router.ex               # API + web routes
        controllers/
          api_controller.ex     # REST API with input validation
        plugs/
          verify_signature.ex   # Ed25519 auth + replay protection
          rate_limiter.ex       # Token bucket rate limiting
          cors.ex               # CORS policy
          api_error_handler.ex  # Safe error responses
          cache_body_reader.ex  # Raw body caching for signatures
        live/
          team_live.ex          # LiveView — team creation UI
    config/
    test/
  cli/                          # Node.js CLI
    src/
      index.ts                  # CLI entry (Commander.js): init, join, apply, diff, status, sync, daemon
      auth.ts                   # Ed25519 keypair gen, storage, signing
      relay-client.ts           # HTTP client: sync, syncCheck, push, pull, createTeam, joinByInvite
      config.ts                 # ~/.teambridge/ config management
      team-spec.ts              # agent-team.yaml parser/validator
      daemon.ts                 # Background sync: chokidar + 2-min polling
      merge.ts                  # Conflict resolution: append-only + last-write-wins
      adapters/
        base.ts                 # PlatformAdapter interface
        claude-code.ts          # Claude Code adapter (agent-team.yaml -> .claude/agents/)
        openclaw.ts             # OpenClaw adapter (agent-team.yaml -> ~/.openclaw/workspace/)
    src/__tests__/
      team-spec.test.ts         # 20 tests
      daemon.test.ts            # 3 tests
      merge.test.ts             # 15 tests
    package.json
    tsconfig.json
  docs/
    plans/
      2026-03-05-teambridge-prd.md
      2026-03-05-teambridge-implementation.md
    security-audit.md
```

---

## Completed Tasks

### Task 1: Security Audit of Auth System
**Status:** Done
**Agent:** security-lead

Reviewed Ed25519 signing system end-to-end. Found 13 issues (2 critical, 4 high, 4 medium, 3 low). Fixed all critical and high issues:

- Added replay protection via `x-tb-timestamp` header (must be within 5 minutes, included in signed message)
- Moved `/api/join` behind auth pipeline (was unauthenticated)
- Fixed `pull` method signing empty string instead of `"GET /path"`
- Added BOLA check (token must match signing key)
- Fixed directory permissions (`~/.teambridge` now 0o700)

Audit documented in `docs/security-audit.md`.

### Task 2: Design agent-team.yaml Schema and Parser
**Status:** Done
**Agent:** spec-designer

Created `cli/src/team-spec.ts`:
- Types: `TeamSpec`, `AgentSpec`
- Functions: `readTeamSpec(dir?)`, `writeTeamSpec(spec, dir?)`, `validateTeamSpec(data)`
- Validation: team name format, required fields, duplicate agent name detection
- 20 tests passing

Added `yaml` npm dependency.

### Task 3: Smart Polling Sync on Relay
**Status:** Done
**Agent:** security-lead

Implemented HTTP polling sync (no WebSocket):
- `GET /api/sync/check?token=X&since=T` — lightweight check, returns `{changed: true/false}`
- `last_updated_at` per team in GenServer state
- Content TTL: 24 hours
- Fixed client/server route mismatch (standardized on flat routes)
- `pull` changed to GET
- GET signing includes query string

### Task 4: CLI Daemon with File Watcher and Smart Polling
**Status:** Done
**Agent:** spec-designer

Created `cli/src/daemon.ts`:
- `startDaemon(opts)` returns `{ stop() }` for graceful shutdown
- Chokidar file watcher on `adapter.watchPaths()`
- Immediate push on local file change
- 2-minute poll interval (configurable via `--poll-interval`)
- Self-trigger prevention via hash cache
- Graceful reconnection on relay failure
- SIGINT/SIGTERM handling

### Task 5: Refactor Platform Adapters
**Status:** Done
**Agent:** spec-designer

Both adapters now use `agent-team.yaml` as canonical source:
- `readTeam()` reads from `agent-team.yaml` via `readTeamSpec()`
- `writeTeam()` writes `agent-team.yaml` then applies to platform-native format
- `getHashes()` hashes `agent-team.yaml`
- Added `watchPaths()`, `writeFile()`, `readFile()` to interface

### Task 6: Conflict Resolution
**Status:** Done
**Agent:** spec-designer

Created `cli/src/merge.ts`:
- `mergeKnowledge(local, remote)` — append-only, dedup by SHA-256 hash per line
- `resolveDefinition(local, remoteChange, localModifiedAt)` — last-write-wins by timestamp
- `resolveChange(key, localContent, remoteChange, localModifiedAt)` — dispatcher
- Logs warning on simultaneous edits (tie-break goes to remote)
- Integrated with daemon hash cache
- 15 tests passing

### Task 7: Relay Security Hardening
**Status:** Done
**Agent:** security-lead

Implemented:
- Rate limiting: ETS-backed token bucket, 60 req/min per token (429 on exceed)
- Input validation: path traversal prevention, platform name validation, hash length limits, max 100 files per sync
- Content size: 256KB enforced on sync files
- `createTeam` now includes token in body (was missing, breaking auth)
- Production guard: `skip_auth` ignored in prod builds (compile-time check)
- CORS plug: restrictive by default, configurable allowlist
- Error handler: generic 500s, no stack traces to client
- Tests for all security measures

New files: `rate_limiter.ex`, `cors.ex`, `api_error_handler.ex`

### Task 8: Update CLI Commands
**Status:** Done
**Agent:** spec-designer

Updated/added commands in `cli/src/index.ts`:
- `init` — detects platform, creates agent-team.yaml, registers with relay
- `join` — downloads team, writes agent-team.yaml, applies to platform
- `apply` — offline: read agent-team.yaml, apply to platform
- `diff` — compare local agent-team.yaml vs relay state
- `status` — show config, agents, relay info
- `daemon` — start background sync process

### Task 9: Integration Fix — Sync Response Shape
**Status:** Done
**Agent:** security-lead

Fixed server to return `{content, updated_at}` objects (not raw strings) from sync endpoint. Required for client-side conflict resolution timestamps. Fixed `createTeam` to return team data in response.

### Task 10: Code Cleanup
**Status:** Done
**Agent:** code-reviewer

Removed dead code across codebase:
- Unused imports in `index.ts`, `openclaw.ts`
- Unused `accepts_json` pipeline in router
- Fixed `pull` tests using POST instead of GET
- Removed unused variable in TTL cleanup test
- Verified all "legacy" functions are still actively called

---

## Test Coverage

| Suite | Tests | Status |
|-------|-------|--------|
| CLI: team-spec | 20 | Passing |
| CLI: daemon | 3 | Passing |
| CLI: merge | 15 | Passing |
| Relay: teams GenServer | ~20 | Passing |
| Relay: API controller | ~25 | Passing |
| Relay: signature verification | ~15 | Passing |
| Relay: security (rate limit, validation) | ~10 | Passing |
| **Total** | **108** | **All passing** |

---

## Post-MVP Fixes (applied after team tasks)

### Fix 11: Multi-platform detection
The CLI now detects all installed platforms. If both `~/.claude` and `~/.openclaw` exist, it prompts:
```
Multiple platforms detected:
  1) claude-code
  2) openclaw
  3) Both
```
Selecting "Both" configures all platforms in one go. All commands support `--platform` override. Changes in `config.ts` (`detectPlatforms()`) and `index.ts` (async `requirePlatform()`).

### Fix 12: Daemon regenerates native agent files
When the daemon receives a remote `agent-team.yaml` change, it now calls `adapter.writeTeam()` to regenerate platform-native files (e.g., `.claude/agents/tb-*.md`). Previously it only wrote the yaml file — agents wouldn't update until manual `teambridge apply`.

### Fix 13: CLAUDE.md team knowledge integration
The CLAUDE.md section written by TeamBridge now instructs agents to read and write `.claude/team-knowledge.md`. This enables agents to naturally share findings — the daemon's file watcher picks up changes and syncs them via the relay.

### Fix 14: Scope prompt text corrected
Changed from incorrect "writes to ~/.claude/teams/" to accurate "creates agents in .claude/agents/ and updates CLAUDE.md" for project scope, and "creates agents in ~/.claude/agents/" for global scope.

### Fix 15: Relay dev binding
`config/runtime.exs` now binds to `{0, 0, 0, 0}` so the relay is accessible from other machines on the network. Previously `runtime.exs` overrode `dev.exs` with just the port, dropping the IP binding.

---

## Remaining Work (Post-MVP)

### Priority 1: Production Readiness
- npm publish CLI package (currently installable via `npm pack` tarball)
- Deployment configuration (Fly.io / Railway)
- HTTPS enforcement
- Monitoring and logging
- Load testing at scale (target: 42K req/s for 5M users)
- Auto-start daemon after `join`/`init`

### Priority 2: Features
- Task coordination system (state machine, assignment, comments)
- MCP server for mid-session reads (`teambridge:read-knowledge`, `teambridge:list-teammates`)
- Additional platform adapters (Cursor, Windsurf)
- SOUL.md editing in web UI
- End-to-end encryption

### Priority 3: Polish
- `teambridge doctor` command (diagnose setup issues)
- Daemon as system service (launchd / systemd)
- Better diff output (colored, side-by-side)
- Conflict resolution UI (show what was merged/overwritten)
- SSH tunnel documentation for cross-machine relay access
