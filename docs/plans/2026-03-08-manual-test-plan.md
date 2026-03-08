# Manual Test Plan — teamrc Multi-Platform

**Date:** 2026-03-08
**Goal:** Verify teamrc works end-to-end across all supported platforms, including rollback/restart scenarios.

**Platforms covered:** Claude Code, Cursor, OpenClaw, Codex, Gemini, Claude Desktop

**Prerequisites:**
- PostgreSQL running (`pg_isready`)
- Relay running (`cd teamrc && mix phx.server`)
- CLI built (`cd cli && npm run build`)
- All platforms installed on the test machine
- Relay defaults to `http://localhost:4000` — no config needed for local dev

---

## Section 1: Fresh Install (From Scratch)

### 1.1 Clean slate

```bash
# Remove ALL teamrc + legacy TeamBridge state
rm -rf ~/.teamrc ~/.teambridge
rm -f .teamrc.yaml agent-team.yaml
rm -f .claude/agents/trc-*.md .claude/agents/tb-*.md .claude/rules/trc-*.md .claude/team-knowledge.md
rm -rf .claude/skills/trc-*
rm -f .cursor/agents/trc-*.md .cursor/agents/tb-*.md .cursor/rules/trc-*.mdc .cursor/rules/tb-*.mdc
rm -rf .cursor/skills/trc-* .cursor/skills/tb-*
rm -f .codex/agents/trc-*.toml .codex/agents/tb-*.toml
rm -f .gemini/agents/trc-*.md
rm -rf .gemini/skills/trc-*
rm -rf ~/.openclaw/workspaces/trc-* ~/.openclaw/workspaces/tb-*
```

**Verify:** `ls ~/.teamrc` → "No such file or directory"

### 1.2 Init with single platform

```bash
npx teamrc init --platform claude-code
```

**Expected:**
- [ ] Keypair generated message
- [ ] Team created on relay
- [ ] `.teamrc.yaml` created in cwd
- [ ] `.claude/agents/trc-agent.md` created
- [ ] Config saved to `~/.teamrc/config.json`
- [ ] Invite code shown

**Verify:**
```bash
cat .teamrc.yaml           # Has name, members, teamId, platforms
cat ~/.teamrc/config.json   # Has token, relay (NO teamId at top level)
ls .claude/agents/trc-*.md  # Agent file(s) present
```

### 1.3 Init with multiple platforms

```bash
# Clean up first (Section 1.1)
npx teamrc init --platform claude-code,cursor,codex,gemini
```

**Expected:**
- [ ] All 4 platforms configured
- [ ] `.teamrc.yaml` lists all 4 in `platforms:`
- [ ] Agent files in `.claude/agents/`, `.cursor/agents/`, `.codex/agents/`, `.gemini/agents/`

### 1.4 Status check

```bash
npx teamrc status
npx teamrc status --json
npx teamrc doctor
```

**Expected:**
- [ ] `status` shows platform, relay, token, team
- [ ] `status --json` returns valid JSON
- [ ] `doctor` shows all checks passing, `.teamrc.yaml` found

---

## Section 2: Team Collaboration (Join Flow)

### 2.1 Create invite

```bash
# On Machine A (already initialized)
npx teamrc invite
```

**Expected:**
- [ ] Invite code shown (`trc_inv_...`)
- [ ] Expiry time shown

### 2.2 Join from another machine/directory

```bash
# From a DIFFERENT directory (simulating Machine B)
mkdir /tmp/teamrc-test-b && cd /tmp/teamrc-test-b

# Clean state for this "machine"
rm -rf ~/.teamrc

npx teamrc join <invite-code> --platform cursor,gemini
```

**Expected:**
- [ ] "Joined team: ..." message
- [ ] `.teamrc.yaml` created with teamId
- [ ] Cursor agents in `.cursor/agents/trc-*.md`
- [ ] Gemini agents in `.gemini/agents/trc-*.md`

### 2.3 Preview without joining

```bash
npx teamrc clone <invite-code> --platform claude-code
```

**Expected:**
- [ ] `.teamrc.yaml` created (no teamId — local copy only)
- [ ] Agent files created
- [ ] "This is a local copy" message

---

## Section 3: Per-Platform Verification

### 3.1 Claude Code

**Init:**
```bash
npx teamrc init --platform claude-code
```

**Verify agent file format:**
```bash
cat .claude/agents/trc-agent.md
```
- [ ] YAML frontmatter with `name:` and `description:`
- [ ] Markdown body with role and soul

**Verify CLAUDE.md update:**
```bash
grep "teamrc" CLAUDE.md
```
- [ ] Team section injected with routing instructions

**Verify rules/skills (if defined):**
```bash
ls .claude/rules/trc-*.md
ls .claude/skills/trc-*/SKILL.md
```

### 3.2 Cursor

**Init:**
```bash
npx teamrc init --platform cursor
```

**Verify:**
```bash
cat .cursor/agents/trc-agent.md     # Agent file
cat .cursor/AGENTS.md               # Routing block
ls .cursor/rules/trc-*.mdc          # Rules (if any)
ls .cursor/skills/trc-*/SKILL.md    # Skills (if any)
```
- [ ] Agent file has proper frontmatter
- [ ] AGENTS.md has `<!-- teamrc:routing -->` markers

### 3.3 Codex

**Init:**
```bash
npx teamrc init --platform codex
```

**Verify:**
```bash
cat .codex/agents/trc-agent.toml    # TOML agent config
cat AGENTS.md                        # Routing block
```
- [ ] TOML has `model`, `instructions` fields
- [ ] AGENTS.md has teamrc section

### 3.4 Gemini

**Init:**
```bash
npx teamrc init --platform gemini
```

**Verify:**
```bash
cat .gemini/agents/trc-agent.md     # Agent file with frontmatter
cat GEMINI.md                        # Routing/knowledge block
ls .gemini/skills/trc-*/SKILL.md    # Skills (if any)
```
- [ ] Agent file has `name:` and `description:` frontmatter
- [ ] GEMINI.md has `<!-- teamrc:routing -->` markers

### 3.5 OpenClaw

**Init:**
```bash
npx teamrc init --platform openclaw
```

**Verify:**
```bash
ls ~/.openclaw/workspaces/trc-*/     # Workspace dirs
cat ~/.openclaw/workspaces/trc-agent/SOUL.md
cat ~/.openclaw/workspaces/trc-agent/AGENTS.md
cat openclaw.json                     # Agent registration
```
- [ ] Workspace has SOUL.md and AGENTS.md
- [ ] openclaw.json has `trc-agent` in agents list
- [ ] `<!-- teamrc:routing -->` markers in openclaw.json agents section

### 3.6 Claude Desktop (via Claude Code adapter)

Claude Desktop uses the same `.claude/agents/` directory as Claude Code.

**Verify:**
```bash
# After init with claude-code
ls ~/.claude/agents/trc-*.md   # Global agents visible to Claude Desktop
```
- [ ] Global scope agents are in `~/.claude/agents/`
- [ ] Project scope agents are in `.claude/agents/`

---

## Section 4: Sync & Daemon

### 4.1 Manual sync

```bash
# On Machine A
npx teamrc sync
```

**Expected:**
- [ ] "Already up to date." or "Applied N change(s)"

### 4.2 Push knowledge

```bash
# Create team knowledge manually
echo "# Team Knowledge\nBug: auth tokens expire after 24h" > .claude/team-knowledge.md
npx teamrc push
```

**Expected:**
- [ ] "Pushed team knowledge."

### 4.3 Diff

```bash
npx teamrc diff
npx teamrc diff --json
```

**Expected:**
- [ ] Shows differences between local and relay
- [ ] JSON mode returns valid JSON

### 4.4 Daemon start/stop

```bash
npx teamrc daemon --poll-interval 5000 --sync-mode knowledge
# Wait 10 seconds, then Ctrl+C
```

**Expected:**
- [ ] "Daemon started. Watching N path(s)"
- [ ] Polls relay periodically
- [ ] Ctrl+C stops cleanly: "Daemon stopped."

### 4.5 Daemon file watch

```bash
# In one terminal:
npx teamrc daemon --poll-interval 60000 --sync-mode all

# In another terminal:
echo "# Updated knowledge" >> .claude/team-knowledge.md
```

**Expected:**
- [ ] Daemon detects file change within ~1 second
- [ ] Pushes to relay

---

## Section 5: Rollback Scenarios

### 5.1 Rollback: Delete and re-init

```bash
# Start fresh
npx teamrc delete
# Confirm with "y"
```

**Expected:**
- [ ] All agent files removed from all platforms
- [ ] `~/.teamrc/` deleted
- [ ] `.teamrc.yaml` deleted
- [ ] `.teamrc.yaml` deleted

**Re-init:**
```bash
npx teamrc init --platform claude-code
```
- [ ] Fresh keypair generated
- [ ] New team created
- [ ] Everything works as in Section 1

### 5.2 Rollback: Re-join after delete

```bash
# Machine A: create team and get invite
npx teamrc init --platform claude-code
npx teamrc invite
# Save the invite code

# Machine A: delete
npx teamrc delete

# Machine A: re-join with same invite
npx teamrc join <saved-invite> --platform claude-code,cursor
```

**Expected:**
- [ ] New keypair (different token)
- [ ] Joined existing team successfully
- [ ] Team data pulled from relay
- [ ] Agent files recreated

### 5.3 Rollback: Uninstall script

```bash
bash scripts/uninstall.sh
```

**Expected:**
- [ ] Config dirs removed
- [ ] `.teamrc.yaml` removed
- [ ] `.teamrc.yaml` removed (if exists)
- [ ] All `trc-*` agent files removed
- [ ] Claude settings cleaned
- [ ] OpenClaw workspaces removed
- [ ] Manual review guidance shown for CLAUDE.md

### 5.4 Rollback: Corrupt config recovery

```bash
# Corrupt config
echo "{invalid json" > ~/.teamrc/config.json

npx teamrc status
```

**Expected:**
- [ ] "teamrc is not initialized" (config treated as missing)

```bash
npx teamrc init --platform claude-code
```

**Expected:**
- [ ] Re-initializes cleanly
- [ ] Old corrupt config overwritten

### 5.5 Rollback: Missing keypair recovery

```bash
rm -f ~/.teamrc/keys/ed25519.*

npx teamrc init --platform claude-code
```

**Expected:**
- [ ] "Generated new keypair."
- [ ] New token (different from before)
- [ ] Everything works

### 5.6 Rollback: Switch between project and global teams

```bash
# Init as project team
npx teamrc init --platform claude-code
# Verify: .teamrc.yaml exists, agents in .claude/agents/

# Delete
npx teamrc delete

# Re-init as global team
npx teamrc init --platform claude-code --global
# Verify: NO .teamrc.yaml, agents in ~/.claude/agents/
```

**Expected:**
- [ ] Project mode: `.teamrc.yaml` + `.claude/agents/trc-*.md`
- [ ] Global mode: `~/.teamrc/config.json` has `globalTeam` + `~/.claude/agents/trc-*.md`

---

## Section 7: Multi-Platform Cross-Sync

### 7.1 Init on multiple platforms, verify all get agents

```bash
npx teamrc init --platform claude-code,cursor,codex,gemini,openclaw
```

**Verify each platform has its agents:**
- [ ] `.claude/agents/trc-agent.md`
- [ ] `.cursor/agents/trc-agent.md`
- [ ] `.codex/agents/trc-agent.toml`
- [ ] `.gemini/agents/trc-agent.md`
- [ ] `~/.openclaw/workspaces/trc-agent/`

### 7.2 Apply with custom team definition

```bash
cat > .teamrc.yaml <<EOF
name: multi-platform-test
teamId: "existing-team-id"
platforms:
  - claude-code
  - cursor
  - gemini
members:
  - name: architect
    role: System design
    soul: "You think in abstractions and design patterns."
    rules: [rule_style]
  - name: implementer
    role: Write code
    rules: [rule_style]
    skills: [skill_search]
rules:
  - id: rule_style
    title: Code Style
    body: "Use prettier and eslint."
skills:
  - id: skill_search
    description: Search the codebase
    body: "Use grep and find."
EOF

npx teamrc apply --platform claude-code,cursor,gemini
```

**Verify:**
- [ ] 2 agents on each platform
- [ ] Rules applied per-agent (only those referenced)
- [ ] Skills applied per-agent

### 7.3 Export → apply roundtrip

```bash
npx teamrc export
# Verify .teamrc.yaml contains relay team data
npx teamrc apply --platform claude-code
# Verify agents match
npx teamrc diff
# Should show "No differences"
```

---

## Section 8: Error Cases

### 8.1 Invalid platform

```bash
npx teamrc init --platform invalid-platform
```
- [ ] Error: "Unknown platform: invalid-platform"

### 8.2 Invalid invite code

```bash
npx teamrc join trc_inv_invalid123
```
- [ ] Error: "invalid_invite" or similar

### 8.3 Relay unreachable

```bash
TEAMRC_RELAY=http://localhost:9999 npx teamrc sync
```
- [ ] Error: "Sync failed: ..." (not a crash)

### 8.4 Oversized YAML

```bash
# Create a YAML larger than 256KB
python3 -c "print('name: big-team\nmembers:\n' + '\n'.join(f'  - name: agent{i}\n    role: role {i}' for i in range(200)))" > .teamrc.yaml
npx teamrc apply --platform claude-code
```
- [ ] Error about max members (100)

### 8.5 Invalid agent names

```bash
cat > .teamrc.yaml <<EOF
name: bad-names
members:
  - name: "../../etc/passwd"
    role: hacker
EOF

npx teamrc apply --platform claude-code
```
- [ ] Error: "Invalid agent name"

---

## Section 9: Full Reset Sequence

Run this entire sequence to verify a complete lifecycle:

```bash
# 1. Clean slate
rm -rf ~/.teamrc
bash scripts/uninstall.sh

# 2. Init
npx teamrc init --platform claude-code,cursor
npx teamrc doctor

# 3. Create invite
INVITE=$(npx teamrc invite 2>&1 | grep trc_inv_)

# 4. Delete everything
npx teamrc delete

# 5. Re-join
npx teamrc join $INVITE --platform claude-code,cursor

# 6. Verify
npx teamrc status
npx teamrc diff

# 7. Sync
npx teamrc sync

# 8. Export
npx teamrc export

# 9. Delete again
npx teamrc delete

# 10. Re-init fresh
npx teamrc init --platform claude-code

# 11. Final verify
npx teamrc doctor
npx teamrc status --json
```

**Pass criteria:** All commands complete without errors. Each step produces expected output.

---

## Section 10: Legacy TeamBridge Cleanup

TeamBridge was the original name of this project. Legacy artifacts use the `tb-` prefix and `~/.teambridge/` config directory. This section verifies that all TeamBridge remnants can be fully removed.

### 10.1 Identify legacy TeamBridge artifacts

```bash
# Config directory
ls -la ~/.teambridge 2>/dev/null && echo "FOUND: ~/.teambridge" || echo "clean"

# Claude Code agents
ls .claude/agents/tb-*.md 2>/dev/null
ls ~/.claude/agents/tb-*.md 2>/dev/null

# Cursor agents and rules
ls .cursor/agents/tb-*.md 2>/dev/null
ls .cursor/rules/tb-*.mdc 2>/dev/null
ls -d .cursor/skills/tb-* 2>/dev/null

# Codex agents
ls .codex/agents/tb-*.toml 2>/dev/null

# OpenClaw workspaces
ls -d ~/.openclaw/workspaces/tb-* 2>/dev/null

# openclaw.json references
grep -l "tb-" openclaw.json 2>/dev/null

# CLAUDE.md references
grep -c "TeamBridge\|teambridge\|tb-" CLAUDE.md 2>/dev/null

# Claude settings hooks
grep -c "teambridge" ~/.claude/settings.json 2>/dev/null

# AGENTS.md / GEMINI.md references
grep -c "TeamBridge\|tb-" AGENTS.md GEMINI.md 2>/dev/null

# .codex/config.toml references
grep -c "tb-" .codex/config.toml 2>/dev/null
```

**Record which artifacts exist before cleanup.**

### 10.2 Run uninstall script

```bash
bash scripts/uninstall.sh
```

**Verify:**
- [ ] `~/.teambridge/` removed
- [ ] `~/.teamrc/` removed
- [ ] All `tb-*.md` agent files removed from `.claude/agents/`
- [ ] All `tb-*.md` agent files removed from `.cursor/agents/`
- [ ] All `tb-*.mdc` rule files removed from `.cursor/rules/`
- [ ] All `tb-*/` skill dirs removed from `.cursor/skills/`
- [ ] All `tb-*.toml` agent files removed from `.codex/agents/`
- [ ] All `tb-*/` OpenClaw workspaces removed from `~/.openclaw/workspaces/`
- [ ] `openclaw.json` cleaned of `tb-*` agent entries
- [ ] Claude `~/.claude/settings.json` cleaned of `teambridge` hooks and `AGENT_TEAMS` env var
- [ ] `CLAUDE.md` flagged for manual review (if TeamBridge section present)
- [ ] `.codex/config.toml` flagged for manual review (if `tb-*` entries present)
- [ ] `.claude/settings.json` and `.claude/settings.local.json` flagged (if references found)

### 10.3 Manual CLAUDE.md cleanup

If the uninstall script flagged CLAUDE.md:

```bash
# Open CLAUDE.md and look for sections like:
# ## TeamBridge Team: ...
# ## teamrc Team: ...
# Any references to tb-* agents
```

- [ ] Remove the `## TeamBridge Team:` section (if present)
- [ ] Remove any `## teamrc Team:` section (if present)
- [ ] Keep any design context or project instructions you wrote yourself
- [ ] Verify no `tb-` or `TeamBridge` references remain

### 10.4 Manual .codex/config.toml cleanup

If flagged:

```bash
# Remove any [[agents]] blocks with tb-* names
grep -n "tb-" .codex/config.toml
```

- [ ] Remove all `[[agents]]` entries with `tb-*` names
- [ ] Keep non-teamrc agent entries

### 10.5 Verify complete cleanup

```bash
# Re-run the identification from 10.1
# EVERY check should return "clean" / no output

# Also check for any remaining references across the project
grep -r "TeamBridge\|teambridge\|tb-" \
  .claude/ .cursor/ .codex/ .gemini/ \
  ~/.openclaw/workspaces/ \
  CLAUDE.md AGENTS.md GEMINI.md \
  openclaw.json .codex/config.toml \
  ~/.claude/settings.json \
  2>/dev/null
```

- [ ] Zero results — all TeamBridge artifacts removed

### 10.6 Fresh init after TeamBridge cleanup

```bash
npx teamrc init --platform claude-code,cursor
```

**Verify:**
- [ ] No errors about conflicting TeamBridge state
- [ ] All new files use `trc-` prefix (not `tb-`)
- [ ] `.teamrc.yaml` created
- [ ] `~/.teamrc/` created (not `~/.teambridge/`)
- [ ] `npx teamrc doctor` passes all checks

### 10.7 CLI delete also cleans TeamBridge leftovers

If you still have TeamBridge artifacts after a fresh init:

```bash
# Create some fake TeamBridge artifacts to test
mkdir -p .claude/agents
echo "legacy" > .claude/agents/tb-old-agent.md
mkdir -p .cursor/agents
echo "legacy" > .cursor/agents/tb-old-agent.md

# Run delete
npx teamrc delete
```

**Verify:**
- [ ] `tb-*.md` files in `.claude/agents/` removed
- [ ] `tb-*.md` files in `.cursor/agents/` removed
- [ ] All `trc-*` files also removed
- [ ] `.teamrc.yaml` removed (if present)

---

## Section 11: Agent Usage Verification (In-Platform)

The goal here is to verify that agents actually work inside each platform — not just that files were created. After each init/apply, open the platform and test that the agents are recognized, respond correctly, and follow team rules.

### 11.1 Claude Code — Agent Selection

**Setup:**
```bash
npx teamrc init --platform claude-code
```

**Test in Claude Code (terminal):**
1. Open a new Claude Code session in the project directory
2. Type: `/agents` or check available agents
   - [ ] `trc-architect` (or team agents) visible in agent list
3. Select an agent and ask a question
   - [ ] Agent responds with its defined role/soul personality
4. Ask the agent: "What are your team rules?"
   - [ ] Agent references rules from `.teamrc.yaml`
5. Check that `CLAUDE.md` team section is respected
   - [ ] Agent knows about team routing (e.g., delegates to correct agent)

### 11.2 Claude Desktop — Agent Visibility

**Setup:** Same as Claude Code (shares `~/.claude/agents/` for global, `.claude/agents/` for project)

**Test in Claude Desktop:**
1. Open Claude Desktop
2. Open the project folder (if project scope) or any folder (if global)
3. Check available agents/personas
   - [ ] teamrc agents appear in the agent picker
4. Select a teamrc agent
   - [ ] Agent responds with the correct role/soul
5. Ask about team context
   - [ ] Agent knows its role within the team

### 11.3 Cursor — Subagent Invocation

**Setup:**
```bash
npx teamrc init --platform cursor
```

**Test in Cursor:**
1. Open the project in Cursor
2. Open Cursor Chat (Cmd+L) or Agent mode
3. Check available agents: type `@` in chat
   - [ ] teamrc agents visible (e.g., `@trc-architect`)
4. Mention an agent: `@trc-architect design the auth flow`
   - [ ] Agent responds with its defined persona
5. Check that `.cursor/AGENTS.md` routing is respected
   - [ ] Cursor routes to the correct agent
6. Check rules in `.cursor/rules/trc-*.mdc`
   - [ ] Rules influence agent behavior (e.g., code style)

### 11.4 Codex — Agent Response

**Setup:**
```bash
npx teamrc init --platform codex
```

**Test in Codex (CLI):**
1. Run codex with the project
2. Check available agents
   - [ ] teamrc agents visible
3. Ask a teamrc agent a question
   - [ ] Responds with role-appropriate behavior
4. Ask about its role: "What is your role on this team?"
   - [ ] Knows its role from the TOML config
5. Verify `AGENTS.md` routing
   - [ ] Agent references correct delegation patterns

### 11.5 Gemini — Agent Chat

**Setup:**
```bash
npx teamrc init --platform gemini
```

**Test in Gemini (gemini.dev or CLI):**
1. Open the project in Gemini
2. Check available agents
   - [ ] teamrc agents visible in `.gemini/agents/`
3. Select an agent
   - [ ] Agent responds with its defined personality
4. Ask about team rules
   - [ ] Agent follows rules from its definition
5. Verify `GEMINI.md` knowledge block
   - [ ] Agent has team context and routing info

### 11.6 OpenClaw — Workspace Agents

**Setup:**
```bash
npx teamrc init --platform openclaw
```

**Test in OpenClaw:**
1. Open OpenClaw
2. Check workspaces
   - [ ] `trc-*` workspaces visible
3. Enter a teamrc workspace
   - [ ] SOUL.md personality is loaded
   - [ ] AGENTS.md routing is present
4. Ask the agent a question
   - [ ] Responds with the defined role/soul
5. Test routing: ask to delegate to another team member
   - [ ] References other team agents correctly

### 11.7 Cross-Platform Consistency

After initializing on ALL platforms, verify consistent behavior:

1. Ask the same question to the same agent across 3+ platforms
   - [ ] Core behavior matches (same role, same rules, same delegation patterns)
   - [ ] Minor formatting differences are acceptable (each platform has its own style)
2. Check that rules produce consistent guidance
   - [ ] All platforms enforce the same code style rules
3. Verify agent delegation
   - [ ] Agents reference the same teammates on all platforms

### 11.8 Team Knowledge Sync Usage

```bash
# Push knowledge from one platform
echo "# Team Knowledge\n\n## Bug Found\nAuth tokens expire silently after 24h." > .claude/team-knowledge.md
npx teamrc push

# Sync on another platform
npx teamrc sync
```

**Verify in each platform:**
- [ ] Agents reference the shared knowledge when relevant
- [ ] Knowledge is visible in the platform's knowledge file
- [ ] Asking "what bugs has the team found?" surfaces the knowledge

### 11.9 Rules Actually Enforced

**Setup:**
```yaml
# .teamrc.yaml
rules:
  - id: rule_no_any
    title: No Any Types
    body: "Never use the `any` type in TypeScript. Always use proper types."
    alwaysApply: true
```

**Test across platforms:**
1. Ask an agent to write TypeScript code
   - [ ] Agent avoids `any` type
2. Show the agent code with `any` and ask for review
   - [ ] Agent flags the `any` usage
3. Repeat on at least 2 platforms
   - [ ] Consistent rule enforcement

### 11.10 Skills Actually Available

**Setup:**
```yaml
# .teamrc.yaml
skills:
  - id: skill_deploy
    description: Deploy to staging
    body: |
      To deploy to staging:
      1. Run `npm run build`
      2. Run `npm run deploy:staging`
      3. Check https://staging.example.com
```

**Test:**
1. Ask an agent with this skill: "How do I deploy to staging?"
   - [ ] Agent references the skill content
   - [ ] Provides the correct deployment steps
2. Ask an agent WITHOUT this skill the same question
   - [ ] Agent does NOT have the deployment steps (skill assignment is explicit-only)

---

## Section 12: Multi-Machine / Multi-VM Sync

Test actual cross-machine sync to verify the relay works end-to-end between separate environments.

### Setup

You need 2 separate machines (or VMs / containers / separate user accounts). Both must be able to reach the relay.

- **Machine A:** Primary development machine
- **Machine B:** Second machine (could be a VM, Docker container, cloud instance, or just a second user account)

```bash
# On Machine B — install teamrc
npm install -g teamrc
# Or use npx for each command
```

### 12.1 Init on Machine A, Join on Machine B

**Machine A:**
```bash
npx teamrc init --platform claude-code,cursor
npx teamrc invite --ttl 1
# Save the invite code
```

**Machine B:**
```bash
npx teamrc join <invite-code> --platform claude-code
```

**Verify on Machine B:**
- [ ] Team joined successfully
- [ ] `.teamrc.yaml` created with same teamId
- [ ] Agent files created in `.claude/agents/`
- [ ] `npx teamrc status` shows same team name and teamId

### 12.2 Push from A, Pull on B

**Machine A:**
```bash
echo "# Team Knowledge\n\n## Finding\nThe auth service has a race condition." > .claude/team-knowledge.md
npx teamrc push
```

**Machine B:**
```bash
npx teamrc sync
```

**Verify on Machine B:**
- [ ] Knowledge file updated with Machine A's content
- [ ] `npx teamrc log` shows the push from Machine A's token

### 12.3 Bidirectional sync

**Machine B:**
```bash
echo "# Debug Notes\nFixed by adding mutex lock." >> .claude/team-knowledge.md
npx teamrc push
```

**Machine A:**
```bash
npx teamrc sync
```

**Verify on Machine A:**
- [ ] Machine B's changes appear in knowledge file
- [ ] Content merged correctly (no data loss)

### 12.4 Daemon sync across machines

**Machine A:**
```bash
npx teamrc daemon --poll-interval 5000 --sync-mode knowledge
```

**Machine B:**
```bash
npx teamrc push
```

**Verify on Machine A (within ~10 seconds):**
- [ ] Daemon logs show remote change detected
- [ ] Knowledge file updated automatically

### 12.5 Concurrent edits (conflict resolution)

**Machine A and B simultaneously:**
```bash
# Machine A:
echo "Machine A edit at $(date)" >> .claude/team-knowledge.md
npx teamrc push

# Machine B (within a few seconds):
echo "Machine B edit at $(date)" >> .claude/team-knowledge.md
npx teamrc push
```

**Then sync both:**
```bash
# Machine A:
npx teamrc sync

# Machine B:
npx teamrc sync
```

**Verify:**
- [ ] No data loss — both edits preserved
- [ ] No crash or error
- [ ] Both machines converge to same state after sync

### 12.6 Machine revocation

**Machine A (with account linked):**
```bash
npx teamrc login
# Link account

# Then revoke Machine B's token via dashboard or API
```

**Machine B:**
```bash
npx teamrc sync
```

**Verify:**
- [ ] Machine B gets 401 or 403 error
- [ ] Clear error message about revocation

### 12.7 Different platforms per machine

**Machine A:**
```bash
npx teamrc init --platform claude-code,cursor
```

**Machine B:**
```bash
npx teamrc join <invite-code> --platform codex,gemini
```

**Verify:**
- [ ] Both machines share the same team definition
- [ ] Machine A has Claude Code + Cursor agents
- [ ] Machine B has Codex + Gemini agents
- [ ] Knowledge sync works across different platform sets

### 12.8 Delete on one machine doesn't affect the other

**Machine B:**
```bash
npx teamrc delete
```

**Machine A:**
```bash
npx teamrc sync
npx teamrc status
```

**Verify:**
- [ ] Machine A still fully functional
- [ ] Team still exists on relay
- [ ] Machine B's deletion only affected Machine B

### 12.9 Re-join after delete on different machine

**Machine B (after delete):**
```bash
# Get fresh invite from Machine A
# Machine A: npx teamrc invite

npx teamrc join <new-invite> --platform gemini
```

**Verify:**
- [ ] New keypair generated (different token)
- [ ] Joined same team
- [ ] All team data pulled from relay
- [ ] Previous Machine B's agent files gone, new ones created

### 12.10 Three-machine scenario

Add a third machine/VM to verify multi-party sync:

```bash
# Machine C:
npx teamrc join <invite-code> --platform openclaw
```

**Verify:**
- [ ] All three machines can push knowledge
- [ ] All three machines receive knowledge from the other two
- [ ] `npx teamrc log` on any machine shows all three tokens
- [ ] Daemon on any machine picks up changes from the other two

---

## Section 13: Account Linking & Device Auth

Test the optional Clerk account linking flow via `teamrc login` and the account linking prompt during `init`/`join`.

### 13.1 Account linking prompt on init

```bash
# Clean slate
rm -rf ~/.teamrc
npx teamrc init --platform claude-code
```

**Expected:**
- [ ] After team creation, prompted: "Link your account for recovery and dashboard access? [Y/n]:"
- [ ] Typing `n` skips linking, shows tip about `teamrc login`
- [ ] Init completes successfully without an account

### 13.2 Account linking prompt on init — accept

```bash
rm -rf ~/.teamrc
npx teamrc init --platform claude-code
# When prompted, press Enter or type "y"
```

**Expected:**
- [ ] Device auth flow starts (shows URL + user code)
- [ ] URL opens in browser (or displays for manual open)
- [ ] Browser shows consent/verification page at `/auth/verify`
- [ ] After browser approval, CLI detects success
- [ ] "Account linked successfully" message
- [ ] `~/.teamrc/config.json` has `account.email` field

### 13.3 Account linking prompt on join

```bash
# From a clean state (different machine or dir)
rm -rf ~/.teamrc
npx teamrc join <invite-code> --platform claude-code
```

**Expected:**
- [ ] After joining team, prompted to link account
- [ ] Same flow as 13.2 if accepted
- [ ] Skip works cleanly if declined

### 13.4 Standalone `teamrc login`

```bash
# Already initialized but NOT linked
npx teamrc login
```

**Expected:**
- [ ] Device auth flow starts
- [ ] Shows: "Open this URL: https://..."
- [ ] Shows: "Your code: XXXX-XXXX"
- [ ] Polls for approval (shows waiting indicator)
- [ ] After browser approval: "Account linked successfully"
- [ ] `~/.teamrc/config.json` updated with `account.email`

### 13.5 `teamrc login` when already linked

```bash
# Already linked from 13.4
npx teamrc login
```

**Expected:**
- [ ] Either: re-links cleanly (updates account)
- [ ] Or: shows "Already linked to <email>"
- [ ] No crash or confusing error

### 13.6 Device auth — browser verification page

Open the URL shown by `teamrc login` in a browser.

**Verify:**
- [ ] Consent screen shows the user code from the CLI
- [ ] Shows machine name
- [ ] "Approve" and "Deny" buttons
- [ ] Approving shows success confirmation
- [ ] Denying shows rejection, CLI gets appropriate error

### 13.7 Device auth — timeout

```bash
npx teamrc login
# Do NOT approve in the browser — wait for timeout
```

**Expected:**
- [ ] CLI eventually times out (not infinite wait)
- [ ] Shows timeout/expiry message
- [ ] Exits cleanly (no crash)

### 13.8 Account recovery scenario

```bash
# Machine A: init + link account
npx teamrc init --platform claude-code
# Link account (accept prompt)

# Machine A: delete everything
npx teamrc delete
rm -rf ~/.teamrc

# Machine A: re-init with same account
npx teamrc init --platform claude-code
# Link account again with same Clerk credentials
```

**Expected:**
- [ ] New keypair generated (different token)
- [ ] Account re-linked to new machine token
- [ ] Previous machines visible in dashboard (if applicable)

### 13.9 Machine management via dashboard

After linking an account:

1. Open the dashboard/web UI
   - [ ] Linked machines listed
   - [ ] Machine name shown
   - [ ] Token (truncated) shown

2. Revoke a machine from the dashboard
   - [ ] Machine removed from list
   - [ ] Revoked machine's `teamrc sync` returns 401/403
   - [ ] Clear error message on revoked machine

### 13.10 Multi-machine account linking

**Machine A:**
```bash
npx teamrc init --platform claude-code
# Link account
```

**Machine B:**
```bash
npx teamrc join <invite-code> --platform cursor
npx teamrc login
# Link SAME Clerk account
```

**Verify:**
- [ ] Both machines linked to same account
- [ ] Dashboard shows both machines
- [ ] Revoking Machine B doesn't affect Machine A
- [ ] Machine A can still sync after Machine B revoked

---

## Platform-Specific Rollback Matrix

| Scenario | Claude Code | Cursor | Codex | Gemini | OpenClaw |
|----------|-------------|--------|-------|--------|----------|
| `init` creates agent files | `.claude/agents/trc-*.md` | `.cursor/agents/trc-*.md` | `.codex/agents/trc-*.toml` | `.gemini/agents/trc-*.md` | `~/.openclaw/workspaces/trc-*/` |
| `delete` removes all artifacts | Yes | Yes | Yes | Yes | Yes |
| `init` after `delete` works | Yes | Yes | Yes | Yes | Yes |
| `join` after `delete` works | Yes | Yes | Yes | Yes | Yes |
| `uninstall.sh` cleans everything | Yes | Yes | Yes | Yes | Yes |
| Global scope supported | `~/.claude/agents/` | N/A (project only) | `~/.codex/agents/` | `~/.gemini/agents/` | Always global |
| `.teamrc.yaml` used (not legacy) | Yes | Yes | Yes | Yes | Yes |
