# Manual Test Plan — teamrc

**Date:** 2026-03-08 (updated 2026-03-12)
**Platforms:** Claude Code, Cursor, Codex, Gemini, OpenClaw, Claude Desktop

---

## Prerequisites

- PostgreSQL running (`pg_isready`)
- Database migrations applied (`cd teamrc && mix ecto.migrate`) — DeviceAuth is now Postgres-backed
- Relay running (`cd teamrc && mix phx.server`)
- CLI built (`cd cli && npm run build`)
- **Note:** Catalog template changes require a server restart (ETS cache is loaded at boot)

```bash
bash scripts/verify/prereqs.sh
```

---

## Quick Reference

| Section | What | Automated? |
|---------|------|------------|
| [1. Init & Setup](#part-1-cli-core) | Fresh install, multi-platform init | `section-01` |
| [2. Collaboration](#2-collaboration) | Invite, join, clone | `section-02` |
| [3. Platform Files](#3-per-platform-file-verification) | Agent file format per platform | `section-03` |
| [4. Sync & Daemon](#4-sync--daemon) | Hash-based sync, conflict detection, daemon | `section-04` |
| [5. Catalog & Members](#5-catalog--team-management) | Templates, add-member | `section-06` |
| [6. Cross-Platform Sync](#6-cross-platform-sync) | Multi-platform apply, export roundtrip | `section-07` |
| [7. Rollback & Recovery](#part-2-robustness) | Delete, re-init, corrupt config | `section-05` |
| [8. Error Cases](#8-error-cases) | Bad input, unreachable relay | `section-08` |
| [9. Full Lifecycle](#9-full-lifecycle) | End-to-end reset sequence | `section-09` |
| [10. Legacy Cleanup](#10-legacy-teambridge-cleanup) | TeamBridge artifact removal | `section-10` |
| [11. Multi-Machine Sync](#part-3-multi-machine) | Cross-machine push/pull/daemon | E2E script |
| [12. Account & Auth](#part-4-account--web) | Device auth, account linking | Partial |
| [13. Team Visibility](#13-team-visibility--clone-tokens) | Public/private, clone tokens (owner only) | Manual only |
| [13b. Share Command](#13b-share-command) | `teamrc share` / `--off` | Manual only |
| [13c. Claim Command](#13c-claim-command) | `teamrc claim <secret>` | Manual only |
| [14. Dashboard CLI](#14-dashboard-command) | `teamrc dashboard` | Manual only |
| [15. Web Dashboard](#15-web-dashboard--account-management) | Dashboard, machines, settings, revoke | Manual only |
| [15b. Auth & Security](#15b-auth--security) | Registration, login, OAuth, ToS, CSRF | Manual only |
| [16. Legal & Guide](#16-legal--guide-pages) | Terms, privacy, guide pages | Manual only |
| [17. In-Platform Usage](#part-5-in-platform-verification) | Agents work inside each IDE | Manual only |

### Verification Scripts

Run after performing the manual action:

```bash
bash scripts/verify/run-all.sh                      # All checks
bash scripts/verify/section-01-fresh-install.sh single|multi
bash scripts/verify/section-02-collaboration.sh join|clone
bash scripts/verify/section-03-platforms.sh claude-code|cursor|codex|gemini|openclaw|all
bash scripts/verify/section-04-sync.sh
bash scripts/verify/section-05-rollback.sh post-delete|post-reinit|post-uninstall|corrupt-config|missing-keypair|scope-project|scope-global
bash scripts/verify/section-06-catalog.sh
bash scripts/verify/section-07-cross-sync.sh
bash scripts/verify/section-08-errors.sh             # Standalone, no setup needed
bash scripts/verify/section-09-lifecycle.sh           # Destructive — runs full lifecycle
bash scripts/verify/section-10-legacy.sh scan|post-uninstall|post-init
bash scripts/verify/section-13-account.sh pre-link|post-link
```

### E2E Test Runner

Automates the full plan across machines, including multi-machine sync.

```bash
# Two-machine setup
bash scripts/test/e2e.sh --role primary --platforms claude-code,cursor    # Machine A
bash scripts/test/e2e.sh --role secondary --invite trc_inv_XXX --platforms claude-code,codex  # Machine B

# Single-machine
bash scripts/test/e2e.sh --role solo

# Specific phase
bash scripts/test/e2e.sh --role primary --phase 3
```

| Phase | Sections | Tests |
|-------|----------|-------|
| 1 | 1.1 | Clean slate + prerequisites |
| 2 | 1–2 | Init (`--team backend`) or join |
| 3 | 3 | Per-platform file verification |
| 3.5 | 5 | Catalog commands + add-member |
| 4 | 4 | Sync, push, diff |
| 5 | 11 | Cross-machine sync |
| 6 | 8 | Error cases |
| 7 | 7 | Delete, re-init, re-join |
| 8 | 10 | Legacy TeamBridge scan |
| 9 | 7.4–7.5 | Corrupt config + missing keypair recovery |
| 10 | — | Final status verification |

---

# Part 1: CLI Core

## 1. Init & Setup

### 1.1 Clean Slate

```bash
bash scripts/clean-slate.sh
```

Removes all teamrc/TeamBridge state: config dirs, agent files, rules, skills, routing sections from `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`/`.codex/config.toml`, entries from `openclaw.json`, Claude settings hooks, and the `.teamrc/` project-level state directory. See `scripts/clean-slate.sh` for details.

Verify: `ls ~/.teamrc` → "No such file or directory", `ls .teamrc` → "No such file or directory"

### 1.2 Init — Single Platform

```bash
npx @teamrc/cli init --platform claude-code
```

- [ ] Keypair generated, team created on relay
- [ ] `.teamrc.yaml` created with `name`, `members`, `teamId`, `platforms`
- [ ] `.teamrc.yaml` does NOT contain `syncHash` fields (sync hashes are in `.teamrc/state.json`)
- [ ] `~/.teamrc/config.json` has `token` (no `relay` — relay is stripped from global config, no `teamId` at top level)
- [ ] `.teamrc/` state directory created in project dir
- [ ] `.gitignore` updated with `.teamrc/` entry
- [ ] `.claude/agents/trc-agent.md` created
- [ ] Invite code shown
- [ ] Ownership token shown (`trc_ocs_...`) with "save this somewhere safe" note — plaintext shown to user, bcrypt hash stored in DB
- [ ] Prompted "Claim ownership now?" — choosing `y` runs device auth + claim, `n` shows `teamrc claim <token>` hint

### 1.3 Init — Already Initialized

```bash
npx @teamrc/cli init --platform claude-code
```

- [ ] Error: `Already initialized: "product-team" (.teamrc.yaml).`
- [ ] Suggests `teamrc apply --platform <platforms>` or `teamrc delete`
- [ ] Exit code 1, no files changed

### 1.4 Init — Multiple Platforms

```bash
bash scripts/clean-slate.sh
npx @teamrc/cli init --platform claude-code,cursor,codex,gemini
```

- [ ] `.teamrc.yaml` lists all 4 in `platforms:`
- [ ] Agent files created per platform (see [Section 3](#3-per-platform-file-verification) for format details)

### 1.5 Status & Doctor

```bash
npx @teamrc/cli status            # Shows platform, relay, token, team
npx @teamrc/cli status --json     # Valid JSON
npx @teamrc/cli doctor            # All checks passing
```

---

## 2. Collaboration

### 2.1 Create Invite

```bash
npx @teamrc/cli invite
```

- [ ] Invite code shown (`trc_inv_...`) with expiry time
- [ ] `npx @teamrc/cli status` confirms team exists on relay (no auth errors)

### 2.2 Join from Another Machine

```bash
mkdir /tmp/teamrc-test-b && cd /tmp/teamrc-test-b
rm -rf ~/.teamrc
npx @teamrc/cli join <invite-code> --platform cursor,gemini
```

- [ ] "Joined team" message, `.teamrc.yaml` created with `teamId`
- [ ] Platform-specific agent files created

### 2.3 Clone via Invite (Preview Only)

```bash
npx @teamrc/cli clone <invite-code> --platform claude-code
```

- [ ] `.teamrc.yaml` created (no `teamId`, no `cloneToken` — local copy only)
- [ ] Agent files created
- [ ] Outro mentions `teamrc join` to connect to the original team

### 2.4 Clone via Clone Token (Public Team)

```bash
npx @teamrc/cli clone <clone-token> --platform claude-code
```

- [ ] `.teamrc.yaml` has `cloneToken` (`trc_cl_...`) and `relay`, no `teamId`
- [ ] Agent files created
- [ ] Outro mentions `teamrc pull` for updates

### 2.5 Pull for Clone-Only Teams

```bash
npx @teamrc/cli pull
```

- [ ] Updates local `.teamrc.yaml` and agent files from relay
- [ ] "Knowledge is not synced for cloned teams." message
- [ ] `cloneToken` and `relay` preserved in YAML

---

## 3. Per-Platform File Verification

After `init` or `join` on a platform, verify the correct file formats.

### 3.1 Claude Code

| Check | Path |
|-------|------|
| Agent file (Markdown + YAML frontmatter) | `.claude/agents/trc-agent.md` |
| Routing section | `CLAUDE.md` — `<!-- teamrc -->` markers |
| Rules | `.claude/rules/trc-*.md` |
| Skills | `.claude/skills/trc-*/SKILL.md` |

### 3.2 Cursor

| Check | Path |
|-------|------|
| Agent file (Markdown + YAML frontmatter) | `.cursor/agents/trc-agent.md` |
| Routing | `.cursor/AGENTS.md` — `<!-- teamrc -->` markers |
| Rules | `.cursor/rules/trc-*.mdc` |
| Skills | `.cursor/skills/trc-*/SKILL.md` |

**Cursor readTeam:** The Cursor adapter's `readTeam()` is now fully implemented. Verify:
- [ ] `teamrc status` with Cursor platform shows team members (not empty)
- [ ] `teamrc diff` with Cursor platform compares against relay correctly
- [ ] `teamrc import --platform cursor` reads existing Cursor agent files

### 3.3 Codex

| Check | Path |
|-------|------|
| Agent file (TOML with `developer_instructions`) | `.codex/agents/trc-agent.toml` |
| Config registration (`[agents.trc-agent]` section) | `.codex/config.toml` — `# --- teamrc start ---` markers |
| Routing | `AGENTS.md` — `<!-- teamrc -->` markers |

### 3.4 Gemini

| Check | Path |
|-------|------|
| Agent file (Markdown + YAML frontmatter) | `.gemini/agents/trc-agent.md` |
| Routing / knowledge | `GEMINI.md` — `<!-- teamrc -->` markers |
| Skills (Gemini CLI) | `.agents/skills/trc-*/SKILL.md` |
| Skills (Antigravity) | `.agent/skills/trc-*/SKILL.md` |

### 3.5 OpenClaw

| Check | Path |
|-------|------|
| Agent file (Markdown + YAML frontmatter, OpenHands format) | `.agents/agents/trc-agent.md` |
| Routing | `AGENTS.md` — `<!-- teamrc -->` markers |
| Skills | `.agents/skills/trc-*/SKILL.md` |

### 3.6 Claude Desktop

Shares `.claude/agents/` with Claude Code. Global scope agents go in `~/.claude/agents/`, project scope in `.claude/agents/`.

---

## 4. Sync & Daemon

### 4.1 Manual Sync — Already In Sync

```bash
npx @teamrc/cli sync
```

- [ ] "Already in sync." when local and server hashes match

### 4.1b Sync State File

Sync hashes are now stored in `.teamrc/state.json` (not in `.teamrc.yaml`):

- [ ] After sync: `.teamrc/state.json` exists and is valid JSON
- [ ] `state.json` contains `syncHash`, `syncHashMembers`, `syncHashSkills`, `syncHashKnowledge`
- [ ] `.teamrc.yaml` does NOT contain any `syncHash*` fields
- [ ] `state.json` persists `lastKnownHash` across daemon restarts

### 4.2 Push Knowledge

```bash
echo "new team insight" >> teamrc-knowledge.md
npx @teamrc/cli push
```

- [ ] "Pushed to relay." message
- [ ] `.teamrc/state.json` `syncHash*` fields updated to match server (NOT in `.teamrc.yaml`)
- [ ] Local `teamrc-knowledge.md` has merged content (relay lines + new local line)
- [ ] Knowledge is append-only: relay content preserved, new line appended at bottom

### 4.3 Sync — Local Changes Only

Edit `.teamrc.yaml` members/skills locally (no pull since last sync):

```bash
npx @teamrc/cli sync
```

- [ ] Detects local-only changes, pushes to server
- [ ] "Pushed local changes to relay." or similar
- [ ] Knowledge merge: even if local knowledge file was accidentally overwritten, relay content is preserved (append-only)

### 4.4 Sync — Remote Changes Only

Push from another machine, then on this machine:

```bash
npx @teamrc/cli sync
```

- [ ] Detects server-only changes, pulls from server
- [ ] Agent files and knowledge file updated

### 4.5 Sync — Both Changed (Knowledge Only)

Both machines edit knowledge, then sync:

- [ ] Knowledge merged via append-only dedup (no conflict) at both client and server
- [ ] Both machines converge to same merged knowledge
- [ ] Relay is source of truth for line order; new local lines appended at bottom
- [ ] Duplicate lines (by trimmed content) never created

### 4.6 Sync — Both Changed (Members/Skills Conflict)

Both machines edit members/skills differently, Machine A pushes first:

**Machine B:**
```bash
npx @teamrc/cli sync
```

- [ ] Detects conflict, pulls server version first
- [ ] Warns user about overwritten local member/skill changes
- [ ] No data corruption

### 4.7 Status — Hash Display

```bash
npx @teamrc/cli status
```

- [ ] Shows sync status: "In sync", "Local changes", "Remote changes", "Diverged", or "Never synced"

### 4.8 Diff (Hash-Based)

```bash
npx @teamrc/cli diff              # Human-readable differences
npx @teamrc/cli diff --json       # Valid JSON
```

- [ ] Uses HEAD endpoint first (single lightweight request)
- [ ] If hashes match: "Everything in sync." (no full team fetch)
- [ ] If hashes differ: fetches full team, shows per-section diff (members, skills, knowledge)
- [ ] Skills read from `.teamrc.yaml`, not platform adapter files

### 4.9 Daemon — Start/Stop

```bash
npx @teamrc/cli daemon --poll-interval 5000 --sync-mode knowledge
# Wait 10s, then Ctrl+C
```

- [ ] "Daemon started. Watching N path(s)"
- [ ] Uses lightweight HEAD endpoint for polling (~200 bytes)
- [ ] Only fetches full team when hash changes
- [ ] Ctrl+C: "Daemon stopped." (clean exit)

### 4.10 Daemon — File Watch

```bash
# Terminal 1:
npx @teamrc/cli daemon --poll-interval 60000 --sync-mode all

# Terminal 2:
echo "# Updated knowledge" >> teamrc-knowledge.md
```

- [ ] Daemon detects change within ~1s and pushes to relay
- [ ] `syncHash*` fields in `.teamrc/state.json` updated after push/pull (not in `.teamrc.yaml`)
- [ ] `lastKnownHash` persisted in `.teamrc/state.json` across daemon restarts

---

## 5. Catalog & Team Management

### 5.1 List Templates

```bash
npx @teamrc/cli list-templates            # Label, description, agent/skill count
npx @teamrc/cli list-templates --json     # JSON array with id, label, description, agents, skills, members
```

### 5.2 List Agents

```bash
npx @teamrc/cli list-agents               # Grouped by category, shows name + role
npx @teamrc/cli list-agents --json        # JSON array with category, label, agents
```

- [ ] ~68 agents across categories (Core Development, Language Specialists, Infrastructure, etc.)

### 5.3 Add Member — By Name

```bash
npx @teamrc/cli add-member backend-dev
```

- [ ] "Added backend-dev (Backend developer)" with recommended skills
- [ ] `.teamrc.yaml` updated, agent files created, pushed to relay

### 5.4 Add Member — Duplicate

```bash
npx @teamrc/cli add-member backend-dev    # Already added
```

- [ ] "Agent 'backend-dev' is already on this team" warning, no changes

### 5.5 Add Member — Invalid Name

```bash
npx @teamrc/cli add-member nonexistent-agent-xyz
```

- [ ] "Agent not found in catalog" error, exit code 1

### 5.6 Add Member — Interactive Picker

```bash
npx @teamrc/cli add-member               # No name arg
```

- [ ] Selectable list grouped by category, already-added agents filtered out
- [ ] Ctrl-C cancels gracefully

### 5.7 Add Member — Non-Interactive

```bash
echo "" | npx @teamrc/cli add-member 2>&1
```

- [ ] Error about requiring agent name in non-interactive mode

---

## 6. Cross-Platform Sync

### 6.1 Init All Platforms

```bash
npx @teamrc/cli init --platform claude-code,cursor,codex,gemini,openclaw
```

Verify each platform has agents (see [Section 3](#3-per-platform-file-verification)).

### 6.2 Apply Custom Team Definition

```bash
cat > .teamrc.yaml <<EOF
name: multi-platform-test
teamId: "existing-team-id"
platforms: [claude-code, cursor, gemini]
members:
  - name: architect
    role: System design
    soul: "You think in abstractions and design patterns."
    skills: [skill_style]
  - name: implementer
    role: Write code
    skills: [skill_style, skill_search]
skills:
  - id: skill_style
    description: Code Style
    body: "Use prettier and eslint."
    alwaysApply: true
  - id: skill_search
    description: Search the codebase
    body: "Use grep and find."
EOF
npx @teamrc/cli apply --platform claude-code,cursor,gemini
```

- [ ] 2 agents on each platform
- [ ] `alwaysApply` skills written as native rules (per platform format)
- [ ] On-demand skills written as `SKILL.md` files
- [ ] Skills applied per-agent (only referenced ones)

### 6.3 Export → Apply Roundtrip

```bash
npx @teamrc/cli export
npx @teamrc/cli apply --platform claude-code
npx @teamrc/cli diff                      # "No differences"
```

---

# Part 2: Robustness

## 7. Rollback & Recovery

### 7.1 Delete and Re-Init

The `delete` command now supports a `--scope` flag:
- `--scope project` — removes `.teamrc.yaml` + `.teamrc/` state dir + platform agent files, keeps `~/.teamrc/`
- `--scope global` — removes `~/.teamrc/team.yaml`, keeps project files and `~/.teamrc/config.json`
- `--scope all` (default with `--yes`) — removes everything

```bash
npx @teamrc/cli delete                    # Shows scope picker (project/global/everything)
```

- [ ] Scope picker shown when no `--scope` flag provided
- [ ] All agent files removed, `~/.teamrc/` deleted, `.teamrc.yaml` deleted, `.teamrc/` state dir deleted

```bash
npx @teamrc/cli init --platform claude-code
```

- [ ] Fresh keypair, new team, everything works as Section 1

### 7.1b Scoped Delete — Project Only

```bash
npx @teamrc/cli delete --scope project
```

- [ ] `.teamrc.yaml` removed
- [ ] `.teamrc/` state directory removed
- [ ] Platform agent files removed
- [ ] `~/.teamrc/` still exists (config.json, keypair preserved)

### 7.1c Scoped Delete — Global Only

```bash
npx @teamrc/cli delete --scope global
```

- [ ] `~/.teamrc/team.yaml` removed
- [ ] `~/.teamrc/config.json` still exists
- [ ] `.teamrc.yaml` still exists
- [ ] `.teamrc/` state dir still exists

### 7.2 Re-Join After Delete

```bash
npx @teamrc/cli init --platform claude-code
npx @teamrc/cli invite                    # Save invite code
npx @teamrc/cli delete
npx @teamrc/cli join <saved-invite> --platform claude-code,cursor
```

- [ ] New keypair (different token), joined existing team, agent files recreated

### 7.3 Uninstall Script

```bash
bash scripts/uninstall.sh
```

- [ ] Config dirs, `.teamrc.yaml`, all `trc-*` agent files removed
- [ ] Claude settings cleaned, OpenClaw workspaces removed
- [ ] Manual review guidance shown for `CLAUDE.md`

### 7.4 Corrupt Config Recovery

```bash
echo "{invalid json" > ~/.teamrc/config.json
npx @teamrc/cli status                   # "teamrc is not initialized"
npx @teamrc/cli init --platform claude-code
```

- [ ] Re-initializes cleanly, corrupt config overwritten

### 7.5 Missing Keypair Recovery

```bash
rm -f ~/.teamrc/key
npx @teamrc/cli init --platform claude-code
```

- [ ] "Generated new keypair." — new token, everything works

### 7.6 Switch Project ↔ Global

```bash
npx @teamrc/cli init --platform claude-code           # Project: .teamrc.yaml + .claude/agents/
npx @teamrc/cli delete
npx @teamrc/cli init --platform claude-code --global   # Global: ~/.teamrc/config.json globalTeam + ~/.claude/agents/
```

---

## 8. Error Cases

| Test | Command | Expected |
|------|---------|----------|
| Invalid platform | `npx @teamrc/cli init --platform invalid-platform` | "Unknown platform" error |
| Invalid invite | `npx @teamrc/cli join trc_inv_invalid123` | "invalid_invite" error |
| Relay unreachable | `TEAMRC_RELAY=http://localhost:9999 npx @teamrc/cli sync` | "Sync failed" (no crash) |
| Too many members | YAML with 200 members → `npx @teamrc/cli apply` | "max members (100)" error |
| Path traversal | Member name `../../etc/passwd` → `npx @teamrc/cli apply` | "Invalid agent name" error |

### 8.1 API Version Header

All CLI requests include `X-Teamrc-Version` header. The server enforces a minimum version.

- [ ] All CLI HTTP requests include the `X-Teamrc-Version` header
- [ ] Server returns 426 (Upgrade Required) when CLI version is below the minimum supported version
- [ ] 426 response includes a clear message telling the user to update the CLI

---

## 9. Full Lifecycle

Run the full sequence end-to-end:

```bash
bash scripts/clean-slate.sh                              # 1. Clean slate
npx @teamrc/cli init --platform claude-code,cursor           # 2. Init
# Verify: .teamrc/ state dir created, .gitignore has .teamrc/
npx @teamrc/cli doctor                                       # 3. Health check
INVITE=$(npx @teamrc/cli invite 2>&1 | grep trc_inv_)        # 4. Create invite
npx @teamrc/cli delete --scope all -y                         # 5. Delete (explicit scope)
# Verify: .teamrc/ state dir removed
npx @teamrc/cli join $INVITE --platform claude-code,cursor    # 6. Re-join
npx @teamrc/cli status && npx @teamrc/cli diff                     # 7. Verify
npx @teamrc/cli sync                                          # 8. Sync
# Verify: .teamrc/state.json exists with syncHash
npx @teamrc/cli export                                        # 9. Export
npx @teamrc/cli delete --scope all -y                         # 10. Delete again
# Verify: .teamrc/ state dir removed
npx @teamrc/cli init --platform claude-code                   # 11. Re-init fresh
npx @teamrc/cli doctor && npx @teamrc/cli status --json            # 12. Final verify
```

**Pass:** All commands complete without errors. `.teamrc/state.json` present after sync, absent after delete.

---

## 10. Legacy TeamBridge Cleanup

TeamBridge was the original project name. Legacy artifacts use `tb-` prefix and `~/.teambridge/`.

### 10.1 Scan for Artifacts

```bash
bash scripts/verify/section-10-legacy.sh scan
```

Or manually check:

```bash
ls -la ~/.teambridge 2>/dev/null
ls .claude/agents/tb-*.md .cursor/agents/tb-*.md .codex/agents/tb-*.toml 2>/dev/null
ls .cursor/rules/tb-*.mdc 2>/dev/null
ls -d .cursor/skills/tb-* ~/.openclaw/workspaces/tb-* .agents/agents/tb-*.md 2>/dev/null
grep -c "TeamBridge\|teambridge\|tb-" CLAUDE.md AGENTS.md GEMINI.md .codex/config.toml ~/.claude/settings.json 2>/dev/null
```

### 10.2 Run Uninstall + Verify

```bash
bash scripts/uninstall.sh
```

- [ ] `~/.teambridge/` and `~/.teamrc/` removed
- [ ] All `tb-*` agent files, rules, skills removed from all platform dirs
- [ ] `~/.claude/settings.json` cleaned of `teambridge` hooks
- [ ] `CLAUDE.md` and `.codex/config.toml` flagged for manual review if they have `tb-` references

### 10.3 Manual Cleanup

If flagged, open `CLAUDE.md` and `.codex/config.toml` and remove any `## TeamBridge Team:` sections or `tb-*` entries.

### 10.4 Verify Clean + Fresh Init

```bash
grep -r "TeamBridge\|teambridge\|tb-" .claude/ .cursor/ .codex/ .gemini/ .agents/ CLAUDE.md AGENTS.md GEMINI.md 2>/dev/null
# → Zero results

npx @teamrc/cli init --platform claude-code,cursor
npx @teamrc/cli doctor                    # All checks pass
```

- [ ] All new files use `trc-` prefix, `.teamrc.yaml`, `~/.teamrc/`

### 10.5 Delete Also Cleans Legacy

```bash
echo "legacy" > .claude/agents/tb-old-agent.md
echo "legacy" > .cursor/agents/tb-old-agent.md
npx @teamrc/cli delete
```

- [ ] Both `tb-*` and `trc-*` files removed

---

# Part 3: Multi-Machine

## 11. Multi-Machine Sync

Requires 2+ separate machines (or VMs/containers). Both must reach the relay.

### 11.1 Init on A, Join on B

**Machine A:**
```bash
npx @teamrc/cli init --platform claude-code,cursor
npx @teamrc/cli invite --ttl 1
```

**Machine B:**
```bash
npx @teamrc/cli join <invite-code> --platform claude-code
```

- [ ] Same `teamId` on both machines, agent files created on B

### 11.2 Push from A, Sync on B

**A:** Push knowledge → **B:** `npx @teamrc/cli sync`
- [ ] Knowledge file updated on B

### 11.3 Bidirectional Sync

**B:** Append to knowledge + push → **A:** `npx @teamrc/cli sync`
- [ ] B's changes appear on A, no data loss

### 11.4 Daemon Cross-Machine

**A:** `npx @teamrc/cli daemon --poll-interval 5000 --sync-mode knowledge`
**B:** `npx @teamrc/cli push`
- [ ] A detects change within ~10s, knowledge file updated automatically

### 11.5 Concurrent Edits — Knowledge Merge

Both machines edit knowledge + push simultaneously, then both sync.
- [ ] Server merges knowledge (append-only dedup) — enforced at server layer in `do_update_team`
- [ ] Client also merges before push (relay content + local additions)
- [ ] No data loss, no crash, both converge to same state
- [ ] Duplicate lines not repeated in merged result
- [ ] Relay line order preserved; new lines appended at bottom

### 11.5b Concurrent Edits — Member/Skill Conflict

Both machines edit members differently + push simultaneously:
- [ ] First push succeeds (fast-forward)
- [ ] Second push gets 409 Conflict with server hash details
- [ ] `teamrc sync` on the losing machine pulls first, then re-pushes

### 11.6 Different Platforms Per Machine

**A:** `claude-code,cursor` — **B:** `codex,gemini`
- [ ] Same team definition, different agent file formats, knowledge sync works

### 11.7 Delete on B Doesn't Affect A

**B:** `npx @teamrc/cli delete` → **A:** `npx @teamrc/cli sync && npx @teamrc/cli status`
- [ ] A still functional, team still on relay

### 11.8 Re-Join After Delete

**B:** `npx @teamrc/cli join <new-invite> --platform gemini`
- [ ] New keypair, joined same team, old files gone, new ones created

### 11.9 Machine Revocation

**A:** Link account + revoke B's token via dashboard → **B:** `npx @teamrc/cli sync`
- [ ] B gets 401/403 with clear revocation error

### 11.10 Three-Machine Scenario

Add Machine C: `npx @teamrc/cli join <invite> --platform openclaw`
- [ ] All three push/receive knowledge, `npx @teamrc/cli log` shows all three tokens

---

# Part 4: Account & Web

## 12. Account Linking & Device Auth

> **Architecture note:** DeviceAuth is now Postgres-backed (was GenServer/in-memory). The UX is unchanged, but `mix ecto.migrate` must be run before testing. Device auth codes now survive server restarts.

### 12.1 Account Linking Prompt on Init

```bash
rm -rf ~/.teamrc
npx @teamrc/cli init --platform claude-code
# Prompted: "Link your account for recovery and dashboard access?"
```

- [ ] `n` → skips linking, shows `teamrc login` tip
- [ ] `y` → device auth flow (URL + user code → browser approval → "Account linked")
- [ ] `~/.teamrc/config.json` gets `account.email` field

### 12.2 Account Linking on Join

Same prompt after `npx @teamrc/cli join`, same flow.

### 12.3 Standalone `teamrc login`

```bash
npx @teamrc/cli login                     # Already initialized but not linked
```

- [ ] Shows URL + user code, polls for approval
- [ ] After browser approval: "Account linked successfully"
- [ ] Config updated with `account.email`
- [ ] Login alone does NOT auto-claim ownership (use `teamrc claim` for that)

### 12.4 Login When Already Linked

```bash
npx @teamrc/cli login                     # Already linked
```

- [ ] Either re-links cleanly or shows "Already linked to \<email\>"

### 12.5 Browser Verification Page (Manual)

Open the URL from `teamrc login`:
- [ ] Redirects to `/users/log-in` if not authenticated (email/password or OAuth sign-in required)
- [ ] After sign-in, consent screen shows user code and machine name
- [ ] "Approve" → success confirmation, CLI detects it
- [ ] "Deny" → rejection, CLI gets error

### 12.6 Timeout (Manual)

```bash
npx @teamrc/cli login                     # Don't approve in browser
```

- [ ] CLI times out (not infinite), shows expiry message, exits cleanly

### 12.7 Account Recovery

```bash
npx @teamrc/cli init --platform claude-code    # Init + link account
npx @teamrc/cli delete && rm -rf ~/.teamrc     # Lose everything
npx @teamrc/cli init --platform claude-code    # Re-init + re-link same email account
```

- [ ] New keypair, account re-linked via same email address, previous machines visible in dashboard

### 12.8 Multi-Machine Linking

**A:** Init + link → **B:** Join + `teamrc login` with same account (email/password or OAuth)
- [ ] Dashboard shows both machines
- [ ] Revoking B doesn't affect A

### 12.9 Ownership Claim via Secret

The claim secret shown during `init` is the plaintext value; the database stores a bcrypt hash. The plaintext cannot be recovered from the DB.

```bash
npx @teamrc/cli init --platform claude-code
# Note the trc_ocs_... token shown during init (plaintext, DB stores bcrypt hash)
npx @teamrc/cli claim <trc_ocs_token>     # Requires linked account
```

- [ ] Without `teamrc login` first → error: "link your account first"
- [ ] After `teamrc login` + `teamrc claim <secret>` → "Ownership claimed."
- [ ] `npx @teamrc/cli share` now works (sets visibility to public)

### 12.10 Claim Secret Cannot Be Reused

```bash
npx @teamrc/cli claim <same-secret>       # Second attempt
```

- [ ] Error: secret is invalid (it was cleared after first claim)

### 12.11 Claim Secret Works for Any Member Who Has It

**A:** Init (gets the `trc_ocs_...` secret), does NOT claim
**B:** Join via invite + `teamrc login`, A gives B the secret

**On B:**
```bash
npx @teamrc/cli claim <A's-secret>
```

- [ ] B becomes owner (the secret is a bearer token — whoever has it can claim)
- [ ] A can no longer claim (secret cleared after use)

### 12.13 Non-Member Cannot Use Claim Secret

**A:** Init (gets the `trc_ocs_...` secret)
**C:** Separate machine, NOT joined to A's team + `teamrc login`

**On C:**
```bash
npx @teamrc/cli claim <A's-secret>
```

- [ ] Error: "you must be a team member to claim ownership"

### 12.12 Web Wizard Sets Owner Directly

Create a team via `/new` while authenticated (email/password or OAuth):
- [ ] Team owner is set immediately (no claim secret needed)
- [ ] Owner can toggle visibility from the team detail page
- [ ] No `trc_ocs_` secret is generated for web-created teams

### 12.14 Registration via Email/Password

1. Navigate to `/users/register`
2. Enter email and password (min 12 chars)
3. Accept Terms of Service checkbox

- [ ] Account created, redirected to dashboard
- [ ] `accepted_terms_at` set on user record
- [ ] Password validation enforced (min 12, max 72 chars)
- [ ] Duplicate email rejected with error

### 12.15 Registration via OAuth (GitHub)

1. Navigate to `/users/log-in`
2. Click "Sign in with GitHub"
3. Authorize on GitHub

- [ ] Redirected to `/users/accept-terms` if first login
- [ ] After ToS acceptance, redirected to dashboard
- [ ] User record has `provider: "github"` and `provider_uid` set
- [ ] Subsequent logins skip ToS acceptance

### 12.16 Registration via OAuth (Google)

Same flow as 12.15 but using "Sign in with Google":
- [ ] Redirected to `/users/accept-terms` if first login
- [ ] User record has `provider: "google"` and `provider_uid` set
- [ ] Email from Google profile stored on user record

### 12.17 ToS Acceptance Flow

1. Log in via OAuth or email/password (new account, no ToS accepted yet)
2. Attempt to access `/dashboard`

- [ ] Redirected to `/users/accept-terms` with flash: "You must accept the Terms of Service to continue."
- [ ] Accepting terms sets `accepted_terms_at` and `terms_version_accepted`
- [ ] After acceptance, redirected to intended destination
- [ ] Subsequent logins no longer require ToS acceptance

---

## 13. Team Visibility & Clone Tokens

### 13.1 Default Visibility

```bash
npx @teamrc/cli status --json             # visibility: "private", no clone token
```

### 13.2 Toggle to Public (Web UI — Owner)

On `/teams/:id` as the team owner, click "Make public":
- [ ] Visibility → "public", clone token generated (`trc_cl_...`), copy button works

### 13.3 Toggle to Public (Web UI — Non-Owner)

On `/teams/:id` as a non-owner team member:
- [ ] Visibility toggle is disabled or hidden
- [ ] If toggled via direct API call, returns 403 error

### 13.4 Toggle Back to Private

As owner, click "Make private":
- [ ] Visibility → "private", clone token preserved (not cleared)
- [ ] Clone API returns 404 for the token (team no longer public)
- [ ] Toggling back to public reuses the same clone token

### 13.5 Clone Token Access

```bash
# When public:
npx @teamrc/cli clone <clone-token> --platform claude-code
# → .teamrc.yaml with cloneToken + relay, no teamId

# When private (old token):
npx @teamrc/cli clone <old-clone-token> --platform claude-code
# → Error: not found / not public
```

### 13.6 Public Team Page (Unauthenticated)

Open `/teams/:id` in incognito for a public team:
- [ ] Preview visible (name, members, skills), clone token shown
- [ ] Knowledge NOT shown, no edit controls

### 13.7 Private Team Page (Unauthenticated)

- [ ] Access denied or redirect, no data visible

### 13.8 Clone API

```bash
curl http://localhost:4000/api/teams/clone/<clone-token>   # 200, team data, no knowledge
curl http://localhost:4000/api/teams/clone/trc_cl_invalid   # 404, no data leaked
```

### 13.9 Visibility API Requires Ownership

```bash
# Non-owner token:
curl -X POST http://localhost:4000/api/teams/visibility \
  -H "Authorization: Bearer <non-owner-token>" \
  -d '{"team_id": "<id>", "visibility": "public"}'
# → 403
```

- [ ] Only owner token gets 200
- [ ] Non-owner token gets 403 with clear error message
- [ ] Unauthenticated request gets 401

---

## 13b. Share Command

### 13b.1 Share Without Linked Account

```bash
npx @teamrc/cli init --platform claude-code    # No teamrc login
npx @teamrc/cli share
```

- [ ] Error: account must be linked (suggests `teamrc login`)
- [ ] Exit code 1, no visibility change

### 13b.2 Share Without Ownership

**A:** Init + claim ownership (init + login + claim)
**B:** Join + login with different account (no claim secret)

**On B:**
```bash
npx @teamrc/cli share
```

- [ ] Error: only the team owner can share
- [ ] Exit code 1, no visibility change

### 13b.3 Share as Owner

```bash
npx @teamrc/cli init --platform claude-code    # Note trc_ocs_... token
npx @teamrc/cli login
npx @teamrc/cli claim <trc_ocs_token>          # Claim ownership
npx @teamrc/cli share
```

- [ ] Team visibility set to "public"
- [ ] Clone token displayed (`trc_cl_...`) with copy-friendly format
- [ ] Shows `teamrc clone <clone-token>` command for sharing
- [ ] `npx @teamrc/cli status --json` confirms `visibility: "public"` and `cloneToken` present

### 13b.4 Share Off (Make Private)

```bash
npx @teamrc/cli share --off
```

- [ ] Team visibility set to "private"
- [ ] Confirmation message shown
- [ ] `npx @teamrc/cli status --json` confirms `visibility: "private"`, no `cloneToken`

### 13b.5 Clone Token Lifecycle

```bash
npx @teamrc/cli share                          # Get clone token
# On another machine:
npx @teamrc/cli clone <clone-token> --platform claude-code
# → Success: .teamrc.yaml with cloneToken, agent files created

npx @teamrc/cli share --off                    # Revoke
# On another machine:
npx @teamrc/cli clone <clone-token> --platform claude-code
# → Error: not found / not public
```

- [ ] Clone token works immediately after `teamrc share`
- [ ] Clone token stops working after `teamrc share --off`
- [ ] Previously cloned copies remain functional (local files persist)
- [ ] `npx @teamrc/cli pull` on a clone after `--off` returns error

### 13b.6 Share Idempotency

```bash
npx @teamrc/cli share                          # Already public
npx @teamrc/cli share                          # Run again
```

- [ ] No error, same clone token returned
- [ ] `teamrc share --off` twice also works without error

---

## 13c. Claim Command

### 13c.1 Claim Without Account

```bash
npx @teamrc/cli init --platform claude-code     # Note the trc_ocs_... token
npx @teamrc/cli claim <trc_ocs_token>
```

- [ ] Error: "link your account first with `teamrc login`"
- [ ] Exit code 1

### 13c.2 Claim with Invalid Secret

```bash
npx @teamrc/cli login
npx @teamrc/cli claim trc_ocs_invalid123
```

- [ ] Error: "invalid or already-claimed ownership token"
- [ ] Exit code 1

### 13c.3 Claim with Wrong Format

```bash
npx @teamrc/cli claim not-a-trc-ocs-token
```

- [ ] Error: "Invalid ownership token. Expected format: trc_ocs_..."
- [ ] Rejected before network call

### 13c.4 Successful Claim

```bash
npx @teamrc/cli init --platform claude-code     # Save the trc_ocs_... token
npx @teamrc/cli login                           # Link account
npx @teamrc/cli claim <trc_ocs_token>
```

- [ ] "Ownership claimed."
- [ ] `teamrc share` now works
- [ ] `teamrc claim <same-token>` again → error (secret cleared after claim)

### 13c.5 Claim During Init

```bash
bash scripts/clean-slate.sh
npx @teamrc/cli init --platform claude-code
# At "Claim ownership now?" prompt, choose yes
```

- [ ] Device auth flow runs inline
- [ ] On success: "Ownership claimed."
- [ ] `teamrc share` works immediately

---

## 14. Dashboard Command

```bash
npx @teamrc/cli dashboard                 # Creates temp invite link, opens browser (24h TTL)
npx @teamrc/cli dashboard --ttl 1         # 1-hour expiry
npx @teamrc/cli dashboard --ttl 0         # Error: TTL must be positive
cd /tmp && npx @teamrc/cli dashboard      # Error: no team context
```

Verify the printed URL loads the team page in browser.

---

## 15. Web Dashboard & Account Management

Requires authentication (email/password or OAuth). Open `/dashboard`.

### 15.1 Access

- [ ] Unauthenticated → redirected to `/users/log-in` with flash: "You must log in to access this page."
- [ ] Authenticated without ToS accepted → redirected to `/users/accept-terms`
- [ ] Authenticated with ToS accepted → shows "Your Teams", "Your Machines", "Account" sections

### 15.2 Teams Section

**With teams:**
- [ ] Teams listed with name (mono), agent count, platform badges, machine count, last activity
- [ ] Click to expand: members with role badges, skill count, participant emails ("you" label)
- [ ] "View team details" → `/teams/:id`

**Empty state:**
- [ ] "No teams yet" + links to `/new` and `teamrc join`

### 15.3 Machines Section

**With machines:**
- [ ] Machine name, truncated token, last seen (human-readable), team associations
- [ ] "Revoke" button → confirmation → machine removed, flash message
- [ ] Revoked machine's sync returns 401/403

**Empty state:**
- [ ] "No machines linked yet" + `teamrc login` instructions

### 15.4 Account Section

- [ ] Shows user email and auth provider (e.g., "email", "github", "google")
- [ ] Sign out link works (redirects to `/`)
- [ ] "Export data" → downloads `teamrc-export.json` (valid JSON: account, machines, teams)
- [ ] "Delete account" → confirmation → account deleted, all tokens revoked, teams persist for others

### 15.5 User Settings (`/users/settings`)

- [ ] Accessible when authenticated (redirects to `/users/log-in` otherwise)
- [ ] Change email: enter new email → confirmation email sent → click link → email updated
- [ ] Change password: enter current password + new password (min 12 chars) → "Password updated successfully!"
- [ ] Password change disconnects all other sessions (LiveView and remember-me)

### 15.6 Password Reset Flow

1. Navigate to `/users/forgot-password`
2. Enter registered email

- [ ] Flash: "If your email is in our system, you will receive reset instructions shortly." (no user enumeration)
- [ ] Email contains reset link (`/users/reset-password/:token`)
- [ ] Clicking link → enter new password → "Password reset successfully."
- [ ] Expired/invalid token → "Reset password link is invalid or it has expired."

### 15.7 Session Management

- [ ] "Remember me" checkbox on login → cookie persists for 14 days
- [ ] Without "Remember me" → session-only cookie (cleared on browser close)
- [ ] Logging out clears session and remember-me cookie
- [ ] Logging out broadcasts disconnect to all LiveView sockets for that session
- [ ] Session token reissued after 7 days of use

### 15.8 Account Deletion (from Settings)

1. Navigate to `/users/settings` or `/dashboard`
2. Click "Delete account" → confirm

- [ ] User record deleted
- [ ] All machine tokens revoked
- [ ] All sessions invalidated
- [ ] Teams persist for other members
- [ ] Redirected to `/` after deletion

---

## 15b. Auth & Security

### 15b.1 Registration — Email/Password

```
Navigate to /users/register
```

- [ ] Email required (valid format, max 160 chars)
- [ ] Password required (min 12, max 72 chars, confirmation must match)
- [ ] Terms of Service acceptance required during registration
- [ ] Duplicate email → "has already been taken"
- [ ] Successful registration → logged in, redirected to dashboard

### 15b.2 Registration — OAuth

```
Navigate to /users/log-in → click GitHub or Google
```

- [ ] GitHub: redirected to `/auth/github`, then GitHub authorize page, callback to `/auth/github/callback`
- [ ] Google: redirected to `/auth/google`, then Google authorize page, callback to `/auth/google/callback`
- [ ] New OAuth user → redirected to `/users/accept-terms` (no session until ToS accepted)
- [ ] Returning OAuth user (ToS already accepted) → logged in, redirected to dashboard
- [ ] OAuth user email collision with existing password user → "Authentication failed" error (provider mismatch)

### 15b.3 Login — Email/Password

```
Navigate to /users/log-in
```

- [ ] Valid email + password → "Welcome back!", redirected to return path or `/`
- [ ] Invalid email or password → "Invalid email or password" (no user enumeration)
- [ ] Email field pre-populated after failed attempt
- [ ] "Remember me" checkbox available

### 15b.4 Login — Magic Link

```
Navigate to /users/log-in → request magic link
```

- [ ] Email sent with login link (`/users/log-in/:token`)
- [ ] Clicking valid link → "User confirmed successfully.", logged in
- [ ] Clicking expired/invalid link → "The link is invalid or it has expired."

### 15b.5 Login — OAuth

```
Navigate to /users/log-in → click GitHub or Google
```

- [ ] Existing user with matching provider → logged in
- [ ] Ueberauth failure (denied access, network error) → "Authentication failed. Please try again."

### 15b.6 Password Reset

```
Navigate to /users/forgot-password
```

- [ ] Enter email → flash: "If your email is in our system, you will receive reset instructions shortly."
- [ ] Non-existent email → same flash (prevents user enumeration)
- [ ] Reset link in email → `/users/reset-password/:token`
- [ ] Enter new password (min 12 chars) → "Password reset successfully.", redirected to login
- [ ] All existing sessions disconnected after password reset
- [ ] Invalid/expired token → "Reset password link is invalid or it has expired."
- [ ] Failed validation (short password) → "Failed to reset password. Please try again."

### 15b.7 ToS Acceptance Gate

- [ ] New user (no `accepted_terms_at`) accessing `/dashboard` → redirected to `/users/accept-terms`
- [ ] New OAuth user → redirected to `/users/accept-terms` before getting full session
- [ ] API endpoints behind `session_api` pipeline → 403 for users without ToS accepted
- [ ] After accepting terms → `accepted_terms_at` and `terms_version_accepted` set
- [ ] Redirected to original destination after acceptance
- [ ] `GET /users/log-in/terms-accepted` renews session for already-authenticated user who just accepted

### 15b.8 Session Security

- [ ] Session token stored in server-side session (not exposed to JavaScript)
- [ ] Remember-me cookie is `HttpOnly`, `Secure`, `SameSite=Lax`, 14-day max age
- [ ] CSRF token regenerated on login/logout (via `renew_session`)
- [ ] Logging out broadcasts `disconnect` to all LiveView sockets for the session
- [ ] Password change disconnects all other sessions

### 15b.9 OAuth Provider Mismatch

1. Register via GitHub (email: user@example.com)
2. Try to register via Google with same email

- [ ] Returns "Authentication failed" error
- [ ] Original account remains intact
- [ ] User can still log in via original provider (GitHub)

### 15b.10 Device Auth Full Flow

1. `npx @teamrc/cli login` → CLI shows URL + user code
2. Open URL in browser → redirected to `/users/log-in` if not authenticated
3. Sign in (email/password or OAuth) → consent screen with user code
4. Approve → CLI receives confirmation

- [ ] CLI polls `/api/auth/device/:device_code` until approved
- [ ] After approval, `~/.teamrc/config.json` gets `account.email`
- [ ] Device auth works with both email/password and OAuth accounts

### 15b.11 PII Protection

- [ ] Participant emails hashed in dashboard (`Teamrc.PII.email_hash/1`)
- [ ] Participant emails hashed in team detail page
- [ ] Participant emails hashed in export data
- [ ] `X-PII-Level` header controls PII disclosure level in API responses

### 15b.12 CSRF / VerifyOrigin

- [ ] `VerifyOrigin` plug blocks cross-origin requests to session-based API endpoints
- [ ] `protect_from_forgery` plug active on all browser routes
- [ ] CSRF token required for POST/DELETE form submissions
- [ ] API endpoints using signature auth (not session) are not affected by CSRF checks

### 15b.13 Content Security Policy

- [ ] CSP header set on all browser responses
- [ ] `frame-ancestors 'none'` prevents clickjacking
- [ ] `default-src 'self'` restricts resource loading to same origin

---

## 16. Legal & Guide Pages

### 16.1 Terms & Privacy

| Route | Active Tab | Content |
|-------|-----------|---------|
| `/terms` | Terms of Service | 12 sections, pre-release warning banner |
| `/privacy` | Privacy Policy | 10 sections, pre-release warning banner |

- [ ] Tab navigation switches between the two pages

### 16.2 Guide Pages

| Route | Title |
|-------|-------|
| `/guide` | Overview |
| `/guide/get-started` | Getting Started |
| `/guide/concepts` | Concepts |
| `/guide/cli` | CLI |
| `/guide/platforms` | Platforms |
| `/guide/sync` | Sync |
| `/guide/config` | Configuration |
| `/guide/web-ui` | Web UI |
| `/guide/faq` | FAQ |

- [ ] Each page loads, content renders, active tab highlighted, navigation works

### 16.3 Footer

- [ ] Visible on all pages, links to `/terms` and `/privacy` work

---

# Part 5: In-Platform Verification

These tests verify agents actually work inside each IDE — not just that files exist. After init, open the platform and test.

## 17. Agent Usage

### Per-Platform Checklist

For each platform, after `npx @teamrc/cli init --platform <platform>`:

1. **Agent visible** — appears in agent list/picker
2. **Persona works** — responds with defined role/soul personality
3. **Team awareness** — knows its role, references teammates
4. **Rules enforced** — follows rules from `.teamrc.yaml`
5. **Routing works** — delegates to correct agent when asked

### Platform-Specific Notes

| Platform | How to check agents | Notes |
|----------|-------------------|-------|
| Claude Code | `/agents` in terminal | Check `CLAUDE.md` routing |
| Claude Desktop | Agent picker in app | Shares `.claude/agents/` with Claude Code |
| Cursor | `@trc-agent` in chat (Cmd+L) | Check `.cursor/AGENTS.md` routing |
| Codex | Agent list in CLI | Check `AGENTS.md` routing |
| Gemini | Agent list in gemini.dev/CLI | Check `GEMINI.md` routing |
| OpenClaw | Workspace list | Check `AGENTS.md` routing |

### Cross-Platform Consistency

Ask the same question to the same agent on 3+ platforms:
- [ ] Core behavior matches (same role, rules, delegation)
- [ ] Minor formatting differences acceptable

### Knowledge Sync Usage

```bash
echo "# Team Knowledge\n\n## Bug Found\nAuth tokens expire silently after 24h." > teamrc-knowledge.md
npx @teamrc/cli push
npx @teamrc/cli sync                      # On another platform
```

- [ ] Agents reference shared knowledge when relevant

### Rules Enforcement

Define a skill with `alwaysApply: true` (e.g., "Never use `any` in TypeScript"). Verify across 2+ platforms:
- [ ] Agent avoids the pattern
- [ ] Agent flags violations in code review

### Skill Availability

Define an on-demand skill (e.g., deployment steps). Verify:
- [ ] Agent WITH the skill references it when asked
- [ ] Agent WITHOUT the skill does NOT have the information

---

## Platform File Reference

| Platform | Agent Path | Skill Path | Routing File |
|----------|-----------|------------|-------------|
| Claude Code | `.claude/agents/trc-*.md` | `.claude/skills/trc-*/SKILL.md`, `.claude/rules/trc-*.md` | `CLAUDE.md` |
| Cursor | `.cursor/agents/trc-*.md` | `.cursor/skills/trc-*/SKILL.md`, `.cursor/rules/trc-*.mdc` | `.cursor/AGENTS.md` |
| Codex | `.codex/agents/trc-*.toml` | (inline in `AGENTS.md`) | `AGENTS.md`, `.codex/config.toml` |
| Gemini | `.gemini/agents/trc-*.md` | `.agents/skills/trc-*/SKILL.md`, `.agent/skills/trc-*/SKILL.md` | `GEMINI.md` |
| OpenClaw | `~/.openclaw/workspace-trc-*/` | `.agents/skills/trc-*/SKILL.md` | `AGENTS.md` |
| Claude Desktop | `~/.claude/agents/trc-*.md` | (same as Claude Code) | — |

**Note:** `.agents/skills/` is the Gemini CLI cross-platform skill alias (takes precedence over `.gemini/skills/`). `.agent/skills/` (singular) is mirrored for Google Antigravity compatibility.
