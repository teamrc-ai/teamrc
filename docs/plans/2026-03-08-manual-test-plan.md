# Manual Test Plan — teamrc

**Date:** 2026-03-08 (updated 2026-03-10)
**Platforms:** Claude Code, Cursor, Codex, Gemini, OpenClaw, Claude Desktop

---

## Prerequisites

- PostgreSQL running (`pg_isready`)
- Relay running (`cd teamrc && mix phx.server`)
- CLI built (`cd cli && npm run build`)

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
| [4. Sync & Daemon](#4-sync--daemon) | Push, pull, diff, daemon | `section-04` |
| [5. Catalog & Members](#5-catalog--team-management) | Templates, add-member | `section-06` |
| [6. Cross-Platform Sync](#6-cross-platform-sync) | Multi-platform apply, export roundtrip | `section-07` |
| [7. Rollback & Recovery](#part-2-robustness) | Delete, re-init, corrupt config | `section-05` |
| [8. Error Cases](#8-error-cases) | Bad input, unreachable relay | `section-08` |
| [9. Full Lifecycle](#9-full-lifecycle) | End-to-end reset sequence | `section-09` |
| [10. Legacy Cleanup](#10-legacy-teambridge-cleanup) | TeamBridge artifact removal | `section-10` |
| [11. Multi-Machine Sync](#part-3-multi-machine) | Cross-machine push/pull/daemon | E2E script |
| [12. Account & Auth](#part-4-account--web) | Device auth, Clerk linking | Partial |
| [13. Team Visibility](#13-team-visibility--clone-tokens) | Public/private, clone tokens (owner only) | Manual only |
| [13b. Share Command](#13b-share-command) | `teamrc share` / `--off` | Manual only |
| [13c. Claim Command](#13c-claim-command) | `teamrc claim <secret>` | Manual only |
| [14. Dashboard CLI](#14-dashboard-command) | `teamrc dashboard` | Manual only |
| [15. Web Dashboard](#15-web-dashboard--account-management) | Clerk dashboard, machines, revoke | Manual only |
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
bash scripts/verify/section-05-rollback.sh post-delete|post-reinit|post-uninstall|corrupt-config|missing-keypair
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
| 2 | 1–2 | Init or join |
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

Removes all teamrc/TeamBridge state: config dirs, agent files, rules, skills, routing sections from `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`/`.codex/config.toml`, entries from `openclaw.json`, and Claude settings hooks. See `scripts/clean-slate.sh` for details.

Verify: `ls ~/.teamrc` → "No such file or directory"

### 1.2 Init — Single Platform

```bash
npx teamrc init --platform claude-code
```

- [ ] Keypair generated, team created on relay
- [ ] `.teamrc.yaml` created with `name`, `members`, `teamId`, `platforms`
- [ ] `~/.teamrc/config.json` has `token`, `relay` (no `teamId` at top level)
- [ ] `.claude/agents/trc-agent.md` created
- [ ] Invite code shown
- [ ] Ownership token shown (`trc_ocs_...`) with "save this somewhere safe" note
- [ ] Prompted "Claim ownership now?" — choosing `y` runs device auth + claim, `n` shows `teamrc claim <token>` hint

### 1.3 Init — Already Initialized

```bash
npx teamrc init --platform claude-code
```

- [ ] Error: `Already initialized: "product-team" (.teamrc.yaml).`
- [ ] Suggests `teamrc apply --platform <platforms>` or `teamrc delete`
- [ ] Exit code 1, no files changed

### 1.4 Init — Multiple Platforms

```bash
bash scripts/clean-slate.sh
npx teamrc init --platform claude-code,cursor,codex,gemini
```

- [ ] `.teamrc.yaml` lists all 4 in `platforms:`
- [ ] Agent files created per platform (see [Section 3](#3-per-platform-file-verification) for format details)

### 1.5 Status & Doctor

```bash
npx teamrc status            # Shows platform, relay, token, team
npx teamrc status --json     # Valid JSON
npx teamrc doctor            # All checks passing
```

---

## 2. Collaboration

### 2.1 Create Invite

```bash
npx teamrc invite
```

- [ ] Invite code shown (`trc_inv_...`) with expiry time
- [ ] `npx teamrc status` confirms team exists on relay (no auth errors)

### 2.2 Join from Another Machine

```bash
mkdir /tmp/teamrc-test-b && cd /tmp/teamrc-test-b
rm -rf ~/.teamrc
npx teamrc join <invite-code> --platform cursor,gemini
```

- [ ] "Joined team" message, `.teamrc.yaml` created with `teamId`
- [ ] Platform-specific agent files created

### 2.3 Clone via Invite (Preview Only)

```bash
npx teamrc clone <invite-code> --platform claude-code
```

- [ ] `.teamrc.yaml` created (no `teamId`, no `cloneToken` — local copy only)
- [ ] Agent files created
- [ ] Outro mentions `teamrc join` to connect to the original team

### 2.4 Clone via Clone Token (Public Team)

```bash
npx teamrc clone <clone-token> --platform claude-code
```

- [ ] `.teamrc.yaml` has `cloneToken` (`trc_cl_...`) and `relay`, no `teamId`
- [ ] Agent files created
- [ ] Outro mentions `teamrc pull` for updates

### 2.5 Pull for Clone-Only Teams

```bash
npx teamrc pull
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
| Skills | `.gemini/skills/trc-*/SKILL.md` |

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

### 4.1 Manual Sync

```bash
npx teamrc sync
```

- [ ] "Already up to date." or "Applied N change(s)"

### 4.2 Push Knowledge

```bash
echo "# Team Knowledge\nBug: auth tokens expire after 24h" > .claude/team-knowledge.md
npx teamrc push
```

- [ ] "Pushed team knowledge."

### 4.3 Diff

```bash
npx teamrc diff              # Human-readable differences
npx teamrc diff --json       # Valid JSON
```

### 4.4 Daemon — Start/Stop

```bash
npx teamrc daemon --poll-interval 5000 --sync-mode knowledge
# Wait 10s, then Ctrl+C
```

- [ ] "Daemon started. Watching N path(s)"
- [ ] Polls relay periodically
- [ ] Ctrl+C: "Daemon stopped." (clean exit)

### 4.5 Daemon — File Watch

```bash
# Terminal 1:
npx teamrc daemon --poll-interval 60000 --sync-mode all

# Terminal 2:
echo "# Updated knowledge" >> .claude/team-knowledge.md
```

- [ ] Daemon detects change within ~1s and pushes to relay

---

## 5. Catalog & Team Management

### 5.1 List Templates

```bash
npx teamrc list-templates            # Label, description, agent/skill count
npx teamrc list-templates --json     # JSON array with id, label, description, agents, skills, members
```

### 5.2 List Agents

```bash
npx teamrc list-agents               # Grouped by category, shows name + role
npx teamrc list-agents --json        # JSON array with category, label, agents
```

- [ ] ~68 agents across categories (Core Development, Language Specialists, Infrastructure, etc.)

### 5.3 Add Member — By Name

```bash
npx teamrc add-member backend-dev
```

- [ ] "Added backend-dev (Backend developer)" with recommended skills
- [ ] `.teamrc.yaml` updated, agent files created, pushed to relay

### 5.4 Add Member — Duplicate

```bash
npx teamrc add-member backend-dev    # Already added
```

- [ ] "Agent 'backend-dev' is already on this team" warning, no changes

### 5.5 Add Member — Invalid Name

```bash
npx teamrc add-member nonexistent-agent-xyz
```

- [ ] "Agent not found in catalog" error, exit code 1

### 5.6 Add Member — Interactive Picker

```bash
npx teamrc add-member               # No name arg
```

- [ ] Selectable list grouped by category, already-added agents filtered out
- [ ] Ctrl-C cancels gracefully

### 5.7 Add Member — Non-Interactive

```bash
echo "" | npx teamrc add-member 2>&1
```

- [ ] Error about requiring agent name in non-interactive mode

---

## 6. Cross-Platform Sync

### 6.1 Init All Platforms

```bash
npx teamrc init --platform claude-code,cursor,codex,gemini,openclaw
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
npx teamrc apply --platform claude-code,cursor,gemini
```

- [ ] 2 agents on each platform
- [ ] `alwaysApply` skills written as native rules (per platform format)
- [ ] On-demand skills written as `SKILL.md` files
- [ ] Skills applied per-agent (only referenced ones)

### 6.3 Export → Apply Roundtrip

```bash
npx teamrc export
npx teamrc apply --platform claude-code
npx teamrc diff                      # "No differences"
```

---

# Part 2: Robustness

## 7. Rollback & Recovery

### 7.1 Delete and Re-Init

```bash
npx teamrc delete                    # Confirm with "y"
```

- [ ] All agent files removed, `~/.teamrc/` deleted, `.teamrc.yaml` deleted

```bash
npx teamrc init --platform claude-code
```

- [ ] Fresh keypair, new team, everything works as Section 1

### 7.2 Re-Join After Delete

```bash
npx teamrc init --platform claude-code
npx teamrc invite                    # Save invite code
npx teamrc delete
npx teamrc join <saved-invite> --platform claude-code,cursor
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
npx teamrc status                   # "teamrc is not initialized"
npx teamrc init --platform claude-code
```

- [ ] Re-initializes cleanly, corrupt config overwritten

### 7.5 Missing Keypair Recovery

```bash
rm -f ~/.teamrc/key
npx teamrc init --platform claude-code
```

- [ ] "Generated new keypair." — new token, everything works

### 7.6 Switch Project ↔ Global

```bash
npx teamrc init --platform claude-code           # Project: .teamrc.yaml + .claude/agents/
npx teamrc delete
npx teamrc init --platform claude-code --global   # Global: ~/.teamrc/config.json globalTeam + ~/.claude/agents/
```

---

## 8. Error Cases

| Test | Command | Expected |
|------|---------|----------|
| Invalid platform | `npx teamrc init --platform invalid-platform` | "Unknown platform" error |
| Invalid invite | `npx teamrc join trc_inv_invalid123` | "invalid_invite" error |
| Relay unreachable | `TEAMRC_RELAY=http://localhost:9999 npx teamrc sync` | "Sync failed" (no crash) |
| Too many members | YAML with 200 members → `npx teamrc apply` | "max members (100)" error |
| Path traversal | Member name `../../etc/passwd` → `npx teamrc apply` | "Invalid agent name" error |

---

## 9. Full Lifecycle

Run the full sequence end-to-end:

```bash
bash scripts/clean-slate.sh                              # 1. Clean slate
npx teamrc init --platform claude-code,cursor           # 2. Init
npx teamrc doctor                                       # 3. Health check
INVITE=$(npx teamrc invite 2>&1 | grep trc_inv_)        # 4. Create invite
npx teamrc delete                                       # 5. Delete
npx teamrc join $INVITE --platform claude-code,cursor    # 6. Re-join
npx teamrc status && npx teamrc diff                     # 7. Verify
npx teamrc sync                                          # 8. Sync
npx teamrc export                                        # 9. Export
npx teamrc delete                                        # 10. Delete again
npx teamrc init --platform claude-code                   # 11. Re-init fresh
npx teamrc doctor && npx teamrc status --json            # 12. Final verify
```

**Pass:** All commands complete without errors.

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

npx teamrc init --platform claude-code,cursor
npx teamrc doctor                    # All checks pass
```

- [ ] All new files use `trc-` prefix, `.teamrc.yaml`, `~/.teamrc/`

### 10.5 Delete Also Cleans Legacy

```bash
echo "legacy" > .claude/agents/tb-old-agent.md
echo "legacy" > .cursor/agents/tb-old-agent.md
npx teamrc delete
```

- [ ] Both `tb-*` and `trc-*` files removed

---

# Part 3: Multi-Machine

## 11. Multi-Machine Sync

Requires 2+ separate machines (or VMs/containers). Both must reach the relay.

### 11.1 Init on A, Join on B

**Machine A:**
```bash
npx teamrc init --platform claude-code,cursor
npx teamrc invite --ttl 1
```

**Machine B:**
```bash
npx teamrc join <invite-code> --platform claude-code
```

- [ ] Same `teamId` on both machines, agent files created on B

### 11.2 Push from A, Sync on B

**A:** Push knowledge → **B:** `npx teamrc sync`
- [ ] Knowledge file updated on B

### 11.3 Bidirectional Sync

**B:** Append to knowledge + push → **A:** `npx teamrc sync`
- [ ] B's changes appear on A, no data loss

### 11.4 Daemon Cross-Machine

**A:** `npx teamrc daemon --poll-interval 5000 --sync-mode knowledge`
**B:** `npx teamrc push`
- [ ] A detects change within ~10s, knowledge file updated automatically

### 11.5 Concurrent Edits

Both machines edit + push simultaneously, then both sync.
- [ ] No data loss, no crash, both converge to same state

### 11.6 Different Platforms Per Machine

**A:** `claude-code,cursor` — **B:** `codex,gemini`
- [ ] Same team definition, different agent file formats, knowledge sync works

### 11.7 Delete on B Doesn't Affect A

**B:** `npx teamrc delete` → **A:** `npx teamrc sync && npx teamrc status`
- [ ] A still functional, team still on relay

### 11.8 Re-Join After Delete

**B:** `npx teamrc join <new-invite> --platform gemini`
- [ ] New keypair, joined same team, old files gone, new ones created

### 11.9 Machine Revocation

**A:** Link account + revoke B's token via dashboard → **B:** `npx teamrc sync`
- [ ] B gets 401/403 with clear revocation error

### 11.10 Three-Machine Scenario

Add Machine C: `npx teamrc join <invite> --platform openclaw`
- [ ] All three push/receive knowledge, `npx teamrc log` shows all three tokens

---

# Part 4: Account & Web

## 12. Account Linking & Device Auth

### 12.1 Account Linking Prompt on Init

```bash
rm -rf ~/.teamrc
npx teamrc init --platform claude-code
# Prompted: "Link your account for recovery and dashboard access?"
```

- [ ] `n` → skips linking, shows `teamrc login` tip
- [ ] `y` → device auth flow (URL + user code → browser approval → "Account linked")
- [ ] `~/.teamrc/config.json` gets `account.email` field

### 12.2 Account Linking on Join

Same prompt after `npx teamrc join`, same flow.

### 12.3 Standalone `teamrc login`

```bash
npx teamrc login                     # Already initialized but not linked
```

- [ ] Shows URL + user code, polls for approval
- [ ] After browser approval: "Account linked successfully"
- [ ] Config updated with `account.email`
- [ ] Login alone does NOT auto-claim ownership (use `teamrc claim` for that)

### 12.4 Login When Already Linked

```bash
npx teamrc login                     # Already linked
```

- [ ] Either re-links cleanly or shows "Already linked to \<email\>"

### 12.5 Browser Verification Page (Manual)

Open the URL from `teamrc login`:
- [ ] Consent screen shows user code and machine name
- [ ] "Approve" → success confirmation, CLI detects it
- [ ] "Deny" → rejection, CLI gets error

### 12.6 Timeout (Manual)

```bash
npx teamrc login                     # Don't approve in browser
```

- [ ] CLI times out (not infinite), shows expiry message, exits cleanly

### 12.7 Account Recovery

```bash
npx teamrc init --platform claude-code    # Init + link account
npx teamrc delete && rm -rf ~/.teamrc     # Lose everything
npx teamrc init --platform claude-code    # Re-init + re-link same Clerk account
```

- [ ] New keypair, account re-linked, previous machines visible in dashboard

### 12.8 Multi-Machine Linking

**A:** Init + link → **B:** Join + `teamrc login` with same Clerk account
- [ ] Dashboard shows both machines
- [ ] Revoking B doesn't affect A

### 12.9 Ownership Claim via Secret

```bash
npx teamrc init --platform claude-code
# Note the trc_ocs_... token shown during init
npx teamrc claim <trc_ocs_token>     # Requires linked account
```

- [ ] Without `teamrc login` first → error: "link your account first"
- [ ] After `teamrc login` + `teamrc claim <secret>` → "Ownership claimed."
- [ ] `npx teamrc share` now works (sets visibility to public)

### 12.10 Claim Secret Cannot Be Reused

```bash
npx teamrc claim <same-secret>       # Second attempt
```

- [ ] Error: secret is invalid (it was cleared after first claim)

### 12.11 Claim Secret Works for Any Member Who Has It

**A:** Init (gets the `trc_ocs_...` secret), does NOT claim
**B:** Join via invite + `teamrc login`, A gives B the secret

**On B:**
```bash
npx teamrc claim <A's-secret>
```

- [ ] B becomes owner (the secret is a bearer token — whoever has it can claim)
- [ ] A can no longer claim (secret cleared after use)

### 12.13 Non-Member Cannot Use Claim Secret

**A:** Init (gets the `trc_ocs_...` secret)
**C:** Separate machine, NOT joined to A's team + `teamrc login`

**On C:**
```bash
npx teamrc claim <A's-secret>
```

- [ ] Error: "you must be a team member to claim ownership"

### 12.12 Web Wizard Sets Owner Directly

Create a team via `/new` while logged into Clerk:
- [ ] Team owner is set immediately (no claim secret needed)
- [ ] Owner can toggle visibility from the team detail page
- [ ] No `trc_ocs_` secret is generated for web-created teams

---

## 13. Team Visibility & Clone Tokens

### 13.1 Default Visibility

```bash
npx teamrc status --json             # visibility: "private", no clone token
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
npx teamrc clone <clone-token> --platform claude-code
# → .teamrc.yaml with cloneToken + relay, no teamId

# When private (old token):
npx teamrc clone <old-clone-token> --platform claude-code
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
npx teamrc init --platform claude-code    # No teamrc login
npx teamrc share
```

- [ ] Error: account must be linked (suggests `teamrc login`)
- [ ] Exit code 1, no visibility change

### 13b.2 Share Without Ownership

**A:** Init + claim ownership (init + login + claim)
**B:** Join + login with different account (no claim secret)

**On B:**
```bash
npx teamrc share
```

- [ ] Error: only the team owner can share
- [ ] Exit code 1, no visibility change

### 13b.3 Share as Owner

```bash
npx teamrc init --platform claude-code    # Note trc_ocs_... token
npx teamrc login
npx teamrc claim <trc_ocs_token>          # Claim ownership
npx teamrc share
```

- [ ] Team visibility set to "public"
- [ ] Clone token displayed (`trc_cl_...`) with copy-friendly format
- [ ] Shows `teamrc clone <clone-token>` command for sharing
- [ ] `npx teamrc status --json` confirms `visibility: "public"` and `cloneToken` present

### 13b.4 Share Off (Make Private)

```bash
npx teamrc share --off
```

- [ ] Team visibility set to "private"
- [ ] Confirmation message shown
- [ ] `npx teamrc status --json` confirms `visibility: "private"`, no `cloneToken`

### 13b.5 Clone Token Lifecycle

```bash
npx teamrc share                          # Get clone token
# On another machine:
npx teamrc clone <clone-token> --platform claude-code
# → Success: .teamrc.yaml with cloneToken, agent files created

npx teamrc share --off                    # Revoke
# On another machine:
npx teamrc clone <clone-token> --platform claude-code
# → Error: not found / not public
```

- [ ] Clone token works immediately after `teamrc share`
- [ ] Clone token stops working after `teamrc share --off`
- [ ] Previously cloned copies remain functional (local files persist)
- [ ] `npx teamrc pull` on a clone after `--off` returns error

### 13b.6 Share Idempotency

```bash
npx teamrc share                          # Already public
npx teamrc share                          # Run again
```

- [ ] No error, same clone token returned
- [ ] `teamrc share --off` twice also works without error

---

## 13c. Claim Command

### 13c.1 Claim Without Account

```bash
npx teamrc init --platform claude-code     # Note the trc_ocs_... token
npx teamrc claim <trc_ocs_token>
```

- [ ] Error: "link your account first with `teamrc login`"
- [ ] Exit code 1

### 13c.2 Claim with Invalid Secret

```bash
npx teamrc login
npx teamrc claim trc_ocs_invalid123
```

- [ ] Error: "invalid or already-claimed ownership token"
- [ ] Exit code 1

### 13c.3 Claim with Wrong Format

```bash
npx teamrc claim not-a-trc-ocs-token
```

- [ ] Error: "Invalid ownership token. Expected format: trc_ocs_..."
- [ ] Rejected before network call

### 13c.4 Successful Claim

```bash
npx teamrc init --platform claude-code     # Save the trc_ocs_... token
npx teamrc login                           # Link account
npx teamrc claim <trc_ocs_token>
```

- [ ] "Ownership claimed."
- [ ] `teamrc share` now works
- [ ] `teamrc claim <same-token>` again → error (secret cleared after claim)

### 13c.5 Claim During Init

```bash
bash scripts/clean-slate.sh
npx teamrc init --platform claude-code
# At "Claim ownership now?" prompt, choose yes
```

- [ ] Device auth flow runs inline
- [ ] On success: "Ownership claimed."
- [ ] `teamrc share` works immediately

---

## 14. Dashboard Command

```bash
npx teamrc dashboard                 # Creates temp invite link, opens browser (24h TTL)
npx teamrc dashboard --ttl 1         # 1-hour expiry
npx teamrc dashboard --ttl 0         # Error: TTL must be positive
cd /tmp && npx teamrc dashboard      # Error: no team context
```

Verify the printed URL loads the team page in browser.

---

## 15. Web Dashboard & Account Management

Requires Clerk auth. Open `/dashboard`.

### 15.1 Access

- [ ] Unauthenticated → redirected to `/new`
- [ ] Authenticated → shows "Your Teams", "Your Machines", "Account" sections

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

- [ ] Shows Clerk email, "Signed in via Clerk" label, sign out link
- [ ] "Export data" → downloads `teamrc-export.json` (valid JSON: account, machines, teams)
- [ ] "Delete account" → confirmation → account deleted, all tokens revoked, teams persist for others

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

For each platform, after `npx teamrc init --platform <platform>`:

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
echo "# Team Knowledge\n\n## Bug Found\nAuth tokens expire silently after 24h." > .claude/team-knowledge.md
npx teamrc push
npx teamrc sync                      # On another platform
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

| Platform | Agent Format | Agent Path | Routing File |
|----------|-------------|------------|-------------|
| Claude Code | Markdown + YAML frontmatter | `.claude/agents/trc-*.md` | `CLAUDE.md` |
| Cursor | Markdown + YAML frontmatter | `.cursor/agents/trc-*.md` | `.cursor/AGENTS.md` |
| Codex | TOML | `.codex/agents/trc-*.toml` | `AGENTS.md` |
| Gemini | Markdown + YAML frontmatter | `.gemini/agents/trc-*.md` | `GEMINI.md` |
| OpenClaw | Markdown + YAML frontmatter | `.agents/agents/trc-*.md` | `AGENTS.md` |
| Claude Desktop | (same as Claude Code) | `~/.claude/agents/trc-*.md` | — |
