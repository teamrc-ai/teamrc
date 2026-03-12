# Multi-Project Teams Implementation Plan

**Date:** 2026-03-07
**Goal:** Support both global teams (one team everywhere) and project teams (different team per project). Expand platform coverage.

---

## First Principles

A developer needs two modes:

1. **Global team**: "I have a personal crew of agents that follows me across all projects." Installed to `~/.<platform>/agents/`. One team, always available.
2. **Project team**: "This repo has its own team." Installed to `<project>/.<platform>/agents/`. Isolated per project. Different projects can have different teams.

These aren't mutually exclusive. A developer might have a global "personal assistants" team AND per-project teams that overlay.

Every platform except OpenClaw already supports this natively via global vs project directories. OpenClaw needs namespacing because it's global-only.

---

## Problem Statement

Today's `~/.teamrc/config.json` stores one `teamId`. Running `teamrc join` in project Y overwrites project X's team. The config conflates machine identity (keypair, token) with team identity (teamId, platforms).

**Fix:** Split config. Machine identity stays global. Team identity moves to the project (or stays global for global teams).

---

## Architecture

### Two Modes

```
# Mode 1: Global team (--global flag)
~/.teamrc/
  config.json          # Machine identity + global team config
  keys/ed25519.key

# Mode 2: Project team (default)
~/.teamrc/
  config.json          # Machine identity only
  keys/ed25519.key

project-x/
  .teamrc.yaml      # Team definition + teamId + platforms

project-y/
  .teamrc.yaml      # Different team
```

### Global Config

```typescript
interface TeamrcConfig {
  token: string;
  relay: string;
  trustedRelays?: string[];
  account?: { email: string };
  machineName?: string;
  // Only set if using global team mode
  globalTeam?: {
    teamId: string;
    platforms: string[];
    noSync?: boolean;
  };
}
```

### `.teamrc.yaml` (Project Mode)

```yaml
name: frontend-crew
teamId: "uuid-from-relay"
relay: "https://relay.teamrc.dev"    # Optional, overrides global
platforms:
  - claude-code
  - cursor
  - copilot
noSync: false

members:
  - name: architect
    role: System design
    soul: "You think in abstractions..."
    rules: [rule_style]
    skills: [skill_search]

rules:
  - id: rule_style
    body: "Use prettier."

skills:
  - id: skill_search
    description: Search the codebase
```

### Resolution Order

When any command runs:
1. Check for `.teamrc.yaml` in cwd (project team)
2. If not found, check `globalTeam` in `~/.teamrc/config.json`
3. If neither, error: "No team configured"

This means `teamrc sync` works in any directory if a global team is set, and switches to the project team when inside a project with `.teamrc.yaml`.

---

## Scope Mapping Per Platform

| Platform | Global team writes to | Project team writes to |
|----------|----------------------|----------------------|
| **Claude Code** | `~/.claude/agents/trc-*.md` | `.claude/agents/trc-*.md` |
| **Cursor** | `~/.cursor/agents/trc-*.md` | `.cursor/agents/trc-*.md` |
| **Codex** | `~/.codex/agents/trc-*.toml` | `.codex/agents/trc-*.toml` |
| **Gemini** | `~/.gemini/agents/trc-*.md` | `.gemini/agents/trc-*.md` |
| **Copilot** | N/A (no global agent dir) | `.github/agents/trc-*.agent.md` |
| **Amazon Q** | N/A | `.amazonq/cli-agents/trc-*.json` |
| **Windsurf** | N/A | `.windsurf/rules/trc-*.md` |
| **Cline** | N/A | `.clinerules/trc-*.md` |
| **Junie** | N/A | `.junie/skills/trc-*/SKILL.md` |
| **Continue** | N/A | `.continue/rules/trc-*.md` |
| **Augment** | N/A | `.augment/rules/trc-*.md` |
| **OpenClaw** | `~/.openclaw/workspaces/trc-*` | `~/.openclaw/workspaces/trc-{teamSlug}-*` (namespaced) |

Platforms without a global agent directory (Copilot, Amazon Q, Windsurf, Cline, Junie, Continue, Augment) only support project teams. OpenClaw uses namespacing for project teams since everything is global.

---

## Phase 1: Config Split & Dual Mode

### 1.1 Update `TeamrcConfig`

**File:** `cli/src/config.ts`

```typescript
export interface TeamrcConfig {
  token: string;
  relay: string;
  trustedRelays?: string[];
  account?: { email: string };
  machineName?: string;
  globalTeam?: {
    teamId: string;
    platforms: string[];
    noSync?: boolean;
  };
}
```

Remove `teamId`, `platform`, `noSync` as top-level fields.

### 1.2 Extend `TeamDefinition`

**File:** `cli/src/adapters/base.ts`

```typescript
export interface TeamDefinition {
  name: string;
  members: TeamMember[];
  rules?: Rule[];
  skills?: Skill[];
  teamId?: string;
  relay?: string;
  platforms?: string[];
  noSync?: boolean;
}
```

### 1.3 Update `readTeamYaml` / `writeTeamYaml`

**File:** `cli/src/team-yaml.ts`

Parse/write new fields. Validation:
- `teamId`: optional string (UUID or relay-assigned ID)
- `relay`: optional URL, validated format
- `platforms`: optional string array, validated against `VALID_PLATFORMS` whitelist
- `noSync`: optional boolean

### 1.4 Unified context resolution

**File:** `cli/src/index.ts`

Replace `requireClient()` with:

```typescript
interface TeamContext {
  team: TeamDefinition;
  scope: "project" | "global";
  config: TeamrcConfig;
  client: TeamrcClient;
  platforms: string[];
}

function requireTeamContext(): TeamContext {
  // 1. Try project-level .teamrc.yaml
  const yaml = readTeamYaml(".teamrc.yaml");
  if (yaml?.teamId) {
    return buildContext(yaml, "project");
  }

  // 2. Fall back to global team
  const config = loadConfig();
  if (config?.globalTeam?.teamId) {
    return buildContext(globalTeamToDefinition(config), "global");
  }

  console.error("No team configured. Run `teamrc init` or `teamrc join`.");
  process.exit(1);
}
```

### 1.5 Update all commands

- `init`, `join`, `clone`: accept `--global` flag. Without it, write to YAML. With it, write to global config.
- `sync`, `push`, `diff`, `status`, `daemon`, `export`, `delete`, `log`: use `requireTeamContext()`.
- `apply`: use scope from context to determine where adapters write.

---

## Phase 2: Relay Multi-Team Support

### 2.1 GenServer state

**File:** `teamrc/lib/teamrc/teams.ex`

Change `token_teams` mapping from `%{token => team_id}` to `%{token => MapSet.new([team_id, ...])}`.

### 2.2 API changes

- `POST /api/join`: associates token with team (additive, don't replace existing teams)
- `GET /api/teams/:token`: returns `%{teams: [team1, team2, ...]}` (list, not single)
- `POST /api/sync`, `POST /api/push`: require `teamId` in body (already present), route to specific team
- `POST /api/teams`: no change

### 2.3 Database

No migration needed. `token_teams` already has composite unique index on `[token, team_id]`.

---

## Phase 3: Gemini Adapter Rewrite

### 3.1 Use native agent files

**File:** `cli/src/adapters/gemini.ts`

Current adapter flattens everything into `GEMINI.md`. Gemini now supports `.gemini/agents/*.md` with YAML frontmatter. Rewrite to mirror Claude Code adapter:

- Write `.gemini/agents/trc-{slug}.md` with frontmatter (`name`, `description`)
- Write `.gemini/skills/trc-{id}/SKILL.md` (keep, already correct)
- Keep `GEMINI.md` marker block for team routing/knowledge only
- Implement `readTeam()` (parse agent files back)
- Set `supportsSync = true`
- Support both `"project"` and `"global"` scope

### 3.2 Update tests

Rewrite `gemini-rules.test.ts` for individual agent files.

---

## Phase 4: OpenClaw Multi-Team

OpenClaw has no project scope. Everything is in `~/.openclaw/`.

### 4.1 Global team (no namespacing needed)

When scope is `"global"`, use current naming: `trc-{agent}`. Single global team, no collision.

### 4.2 Project team (namespaced)

When scope is `"project"`, namespace by team: `trc-{teamSlug}-{agent}`.

```typescript
private agentWorkspace(teamName: string | null, agentName: string): string {
  const prefix = teamName ? `trc-${slugify(teamName)}-${agentName}` : `trc-${agentName}`;
  return path.join(this.openclawDir, "workspaces", prefix);
}
```

### 4.3 Team-scoped markers and cleanup

- Markers: `<!-- teamrc:{teamSlug}:routing -->` (project) vs `<!-- teamrc:routing -->` (global)
- Cleanup: match `trc-{teamSlug}-*` for project teams, `trc-*` (without second hyphen-separated segment from a known team) for global
- `uninstall(teamName?)` accepts optional team to scope removal

### 4.4 Routing updates

Update `allowAgents` in `openclaw.json` to include only the active team's agents. When switching projects, the CLI updates `allowAgents` to the current team's agents (or all `trc-*` if global).

---

## Phase 5: New Platform Adapters

### 5.1 Copilot Adapter (HIGH priority)

**Why:** Huge user base. Rich agent file format. Already reads `.claude/agents/`.

**File:** `cli/src/adapters/copilot.ts`

| Artifact | Path | Format |
|----------|------|--------|
| Agent profiles | `.github/agents/trc-{slug}.agent.md` | YAML frontmatter (`name`, `description`, `tools`) + markdown body |
| Team rules | `.github/copilot-instructions.md` | Marker block |
| Per-rule files | `.github/instructions/trc-{id}.instructions.md` | YAML frontmatter with `applyTo` globs |

- Project-scoped only (no `~/.github/agents/`)
- `readTeam()`: parse `trc-*.agent.md` files
- `supportsSync = true`

### 5.2 Amazon Q Adapter (HIGH priority)

**Why:** Only other platform with named custom agents. Direct TeamMember → agent mapping.

**File:** `cli/src/adapters/amazon-q.ts`

| Artifact | Path | Format |
|----------|------|--------|
| Agent configs | `.amazonq/cli-agents/trc-{slug}.json` | JSON (`name`, `description`, `prompt`, `tools`) |
| Rules | `.amazonq/rules/trc-{id}.md` | Markdown |

- Project-scoped only
- `readTeam()`: parse JSON agent files
- `supportsSync = true`

### 5.3 Windsurf Adapter (MEDIUM priority)

**File:** `cli/src/adapters/windsurf.ts`

| Artifact | Path | Format |
|----------|------|--------|
| Agent rules | `.windsurf/rules/trc-{slug}.md` | Markdown with activation mode frontmatter |
| Workflows | `.windsurf/workflows/trc-{slug}.md` | Markdown (skills → workflows) |

- Project-scoped. No named agents; rules approximate agent personas via `description` activation.

### 5.4 Cline Adapter (MEDIUM priority)

**File:** `cli/src/adapters/cline.ts`

| Artifact | Path | Format |
|----------|------|--------|
| Rules | `.clinerules/trc-{slug}.md` | Markdown with optional `paths:` frontmatter |

- Project-scoped. Simple format.

### 5.5 Junie Adapter (LOW priority)

| Artifact | Path |
|----------|------|
| Guidelines | `.junie/AGENTS.md` (marker block) |
| Skills | `.junie/skills/trc-{id}/SKILL.md` |

### 5.6 Continue.dev Adapter (LOW priority)

| Artifact | Path |
|----------|------|
| Rules | `.continue/rules/trc-{id}.md` (with YAML frontmatter) |

### 5.7 Augment Adapter (LOW priority)

| Artifact | Path |
|----------|------|
| Rules | `.augment/rules/trc-{slug}.md` (with type frontmatter) |

---

## Phase 6: CLI UX Overhaul

### Design Principles

1. **Show, don't ask**: Auto-detect everything possible. Only prompt when there's a genuine choice.
2. **Instant feedback**: Show a spinner within 100ms of any network call. Never leave users staring at nothing.
3. **Suggest the next step**: After every command, tell the user what to do next.
4. **Machine-friendly**: Every command that produces output supports `--json`. Non-TTY detection skips all prompts.
5. **Consistent language**: Same terminology, same formatting, same symbols everywhere.

### 6.0 Add `@clack/prompts`

**File:** `cli/package.json`

Replace hand-rolled `readline` prompts with `@clack/prompts`. Remove the `askQuestion()` and `askScope()` functions entirely.

```bash
npm install @clack/prompts
```

Key components to use:
- `intro()` / `outro()`: Session start/end
- `text()`: Free-form input with validation
- `select()`: Single selection (replaces numbered lists)
- `multiselect()`: Checkbox multi-selection (for platforms)
- `confirm()`: Yes/no (replaces manual y/N parsing)
- `spinner()`: Loading state for network calls
- `log.info()`, `log.success()`, `log.warn()`, `log.error()`: Structured output
- `note()`: Boxed informational messages
- `isCancel()`: Graceful Ctrl-C handling
- `tasks()`: Sequential task runner with status

### 6.1 Global Flags

Add to the root `program` definition:

```typescript
program
  .option("--json", "Output as JSON")
  .option("-y, --yes", "Skip all prompts, use defaults")
  .option("--no-color", "Disable colored output")
  .option("-v, --verbose", "Show detailed output")
```

Non-TTY detection: if `!process.stdin.isTTY` and a prompt would be needed, fail with a clear error and the flag that would skip it.

### 6.2 `teamrc init`

**Interactive flow (TTY):**

```
$ teamrc init

  teamrc

  Setting up a new team.

◆  Team name
│  frontend-crew
│
◇  Where should this team live?
│  ● This project (agents in .claude/agents/, checked into git)
│  ○ Global (agents in ~/.claude/agents/, all projects)
│
◇  Which platforms? (space to toggle)
│  ◼ claude-code (detected)
│  ◼ cursor (detected)
│  ◻ codex
│  ◼ copilot (detected)
│  ◻ gemini
│  ◻ openclaw
│
◇  Link your account? (optional, for recovery & dashboard)
│  No
│
◒  Creating team on relay...
│
◇  Team created.
│
│  Wrote .teamrc.yaml
│  Applied to: claude-code, cursor, copilot
│
└  Next: Add members to .teamrc.yaml, then run teamrc apply

  Share with teammates:
  ┌──────────────────────────────────────────┐
  │  npx @teamrc/cli join trc_inv_a8f3c9e21b     │
  │  Expires in 24 hours.                    │
  └──────────────────────────────────────────┘
```

**Non-interactive (CI/scripting):**

```bash
teamrc init --yes --name "frontend-crew" --platform claude-code,cursor
```

**Flags:**
- `--name <name>`: Team name (skip prompt)
- `--platform <platforms>`: Comma-separated (skip prompt)
- `--global`: Install globally
- `--yes` / `-y`: Accept all defaults
- `--relay <url>`: Override relay

### 6.3 `teamrc join`

```
$ teamrc join trc_inv_a8f3c9e21b

  teamrc

◒  Joining team...

◇  Joined "backend-squad" (3 members)
│
│  Members:
│    architect    System design
│    implementer  Write code
│    qa-engineer  Test coverage
│
◒  Applying to detected platforms...

◇  Applied.
│    claude-code  3 agents, 2 rules → .claude/agents/
│    cursor       3 agents, 2 rules → .cursor/agents/
│
│  Wrote .teamrc.yaml
│
└  Next: Run teamrc daemon to start live sync
```

**Flags:**
- `--global`: Join as global team
- `--no-sync`: Register but disable auto-sync
- `--platform <platforms>`: Override platform detection
- `--yes` / `-y`: Skip prompts

### 6.4 `teamrc apply`

```
$ teamrc apply

  teamrc

◒  Applying "frontend-crew" to 3 platforms...

  claude-code  5 agents, 3 rules, 2 skills → .claude/agents/
  cursor       5 agents, 3 rules, 2 skills → .cursor/agents/
  copilot      5 agents, 3 rules           → .github/agents/

└  Done. 5 agents across 3 platforms.
```

### 6.5 `teamrc status`

```
$ teamrc status

  teamrc

  Machine   my-laptop
  Identity  trc_ak_abc...xyz
  Relay     https://relay.teamrc.dev  ● connected
  Account   ben@example.com

  Project team: frontend-crew
  ──────────────────────────────────────
  Team ID    uuid-123
  Source     ./.teamrc.yaml
  Platforms  claude-code, cursor, copilot
  Sync       ● enabled (last: 3s ago)
  Members    5 agents
    architect      System design
    implementer    Write code
    qa-engineer    Test coverage
    frontend-dev   UI components
    devops         Infrastructure

  Global team: my-assistants
  ──────────────────────────────────────
  Team ID    uuid-456
  Platforms  claude-code, openclaw
  Sync       ● enabled
  Members    2 agents
    researcher     Deep research
    reviewer       Code review
```

**With `--json`:**

```json
{
  "machine": "my-laptop",
  "token": "trc_ak_abc...xyz",
  "relay": { "url": "https://relay.teamrc.dev", "connected": true },
  "account": "ben@example.com",
  "projectTeam": {
    "name": "frontend-crew",
    "teamId": "uuid-123",
    "platforms": ["claude-code", "cursor", "copilot"],
    "sync": true,
    "members": [...]
  },
  "globalTeam": { ... }
}
```

### 6.6 `teamrc diff`

```
$ teamrc diff

  teamrc

  Comparing local ↔ relay for "frontend-crew"

  Members
    + frontend-dev (UI components)         local only
    ~ architect: role "System design" → "Architecture"
    - legacy-agent (Old stuff)             relay only

  Rules
    + rule_typescript                      local only

  Skills
    (no differences)

└  3 differences. Run teamrc sync to resolve.
```

### 6.7 `teamrc sync`

```
$ teamrc sync

  teamrc

◒  Syncing with relay...

  ↓ 2 changes from relay
    Applied: architect role updated to "Architecture"
    Applied: legacy-agent removed

  ↑ 1 change pushed
    Pushed: frontend-dev added

└  Synced. 3 changes applied.
```

### 6.8 `teamrc doctor`

```
$ teamrc doctor

  teamrc doctor

  ✓ Keypair found
  ✓ Config valid
  ✓ Relay reachable (142ms)
  ✓ .teamrc.yaml found (5 members)
  ✓ Platforms: claude-code, cursor, copilot
  ✓ Agents synced (5 local = 5 relay)
  ! Account not linked (optional)

└  6 checks passed, 1 info. Everything looks good.
```

### 6.9 `teamrc delete`

```
$ teamrc delete

  teamrc

  This will remove all teamrc agents, rules, skills, and knowledge
  from this machine. Other team members keep their setup.

◆  Type "frontend-crew" to confirm deletion:
│  frontend-crew
│

◒  Removing...

  Removed 5 agents from .claude/agents/
  Removed 5 agents from .cursor/agents/
  Removed 5 agents from .github/agents/
  Removed .claude/teamrc-knowledge.md
  Removed .teamrc.yaml
  Cleaned CLAUDE.md

└  Done. Run teamrc init or teamrc join to set up again.
```

### 6.10 `teamrc invite`

```
$ teamrc invite

  teamrc

◒  Creating invite...

  ┌──────────────────────────────────────────┐
  │                                          │
  │  npx @teamrc/cli join trc_inv_a8f3c9e21b     │
  │                                          │
  │  Team:    frontend-crew                  │
  │  Expires: 24 hours                       │
  │                                          │
  └──────────────────────────────────────────┘

└  Share this command with your teammates.
```

### 6.11 `teamrc daemon`

```
$ teamrc daemon

  teamrc daemon

  Watching "frontend-crew" on claude-code, cursor
  Sync mode: knowledge
  Poll interval: 5s

  12:34:01  ↓  Applied: teamrc-knowledge.md updated
  12:34:15  ↑  Pushed: teamrc-knowledge.md (local edit)
  12:35:02  ·  No changes
  ^C

└  Daemon stopped.
```

### 6.12 `teamrc log`

```
$ teamrc log

  teamrc log - frontend-crew

  12:34:01  memory   trc_ak_abc...  claude-code   "Auth bug fixed via JWT rotation"
  12:33:45  agent    trc_ak_def...  cursor        architect role updated
  12:33:12  rule     trc_ak_abc...  claude-code   rule_typescript added

└  3 entries. Use --limit to show more.
```

### 6.13 `teamrc teams` (new)

```
$ teamrc teams

  teamrc teams

  TEAM             SCOPE    SOURCE                  PLATFORMS
  frontend-crew    project  ./.teamrc.yaml       claude-code, cursor, copilot
  my-assistants    global   ~/.teamrc/config.json   claude-code, openclaw

└  2 teams on this machine.
```

### 6.14 Error Handling

All errors use `log.error()` with:
1. What went wrong (clear, specific)
2. Why it might have happened
3. How to fix it

```
$ teamrc sync

  teamrc

  ✗ Sync failed: relay returned 401

  Your machine's token is not registered with this team.
  This can happen if the team was recreated or your token was revoked.

  To fix: Run teamrc join <invite-code> to re-register.
```

Error codes for scripting:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Not initialized (no config/keypair) |
| 3 | Network error (relay unreachable) |
| 4 | Auth error (401/403) |
| 5 | Conflict (merge conflict in sync) |

### 6.15 Config Precedence

Documented and enforced order:

```
1. CLI flags          (--relay, --platform, --name)
2. Environment vars   (TEAMRC_RELAY, TEAMRC_TOKEN, TEAMRC_TEAM_ID)
3. Project config     (.teamrc.yaml in cwd)
4. Global config      (~/.teamrc/config.json)
5. Auto-detection     (detectPlatforms(), default relay)
```

### 6.16 Platform Detection Expansion

**File:** `cli/src/config.ts`

```typescript
const PLATFORM_SIGNALS: Record<string, (home: string, cwd: string) => boolean> = {
  "claude-code": (h) => fs.existsSync(path.join(h, ".claude")),
  "cursor":      (_, c) => fs.existsSync(path.join(c, ".cursor")),
  "codex":       (h, c) => fs.existsSync(path.join(h, ".codex")) || fs.existsSync(path.join(c, ".codex")),
  "gemini":      (h, c) => fs.existsSync(path.join(h, ".gemini")) || fs.existsSync(path.join(c, ".gemini")),
  "openclaw":    (h) => fs.existsSync(path.join(h, ".openclaw")),
  "copilot":     (_, c) => fs.existsSync(path.join(c, ".github")),
  "amazon-q":    (h, c) => fs.existsSync(path.join(h, ".amazonq")) || fs.existsSync(path.join(c, ".amazonq")),
  "windsurf":    (_, c) => fs.existsSync(path.join(c, ".windsurf")),
  "cline":       (_, c) => fs.existsSync(path.join(c, ".clinerules")),
  "junie":       (_, c) => fs.existsSync(path.join(c, ".junie")),
};
```

### 6.17 Dead Code Removal

- Remove `askQuestion()`, replaced by `@clack/prompts`
- Remove `askScope()`, replaced by `--global` flag + `select()`
- Remove `primaryPlatform()`, replaced by `platforms` array
- Remove `requireClient()`, replaced by `requireTeamContext()`
- Remove top-level `teamId`/`platform`/`noSync` from `TeamrcConfig`
- Remove all raw `console.log` calls, replace with `log.*()` from clack

---

## Phase 7: Web UI

### Current State

The web UI has 3 pages:
- **`/new`**: Team creation wizard (3-step: template, configure, success)
- **`/dashboard`**: Machine and team management (Clerk auth required)
- **`/auth/verify`**: Device auth verification for `teamrc login`

Stack: Phoenix LiveView, Tailwind CSS, daisyUI, Clerk auth, light/dark themes.

### 7.1 Team Creation Wizard Updates

#### Platform selection (Step 2)

Add a platform picker to the configure step. Currently the wizard creates a team with members/rules/skills but doesn't specify which platforms the team targets. The CLI handles this, but showing it in the wizard helps the user understand what will happen.

```
Platforms (select all that apply)
┌─────────────────────────────────────────────────┐
│ ◼ Claude Code    ◼ Cursor       ◻ Codex        │
│ ◼ Copilot        ◻ Gemini       ◻ OpenClaw     │
│ ◻ Windsurf       ◻ Cline        ◻ Amazon Q     │
└─────────────────────────────────────────────────┘
```

Store selected platforms in the team definition sent to the relay. The `join` command uses them as defaults (user can override with `--platform`).

#### Success step: expanded join instructions

Show platform-specific instructions after team creation:

```
Your team is ready!

  ┌──────────────────────────────────────────────┐
  │  npx @teamrc/cli join trc_inv_a8f3c9e21b         │
  └──────────────────────────────────────────────┘

  This will:
  1. Download your team definition
  2. Generate agent files for: Claude Code, Cursor, Copilot
  3. Start syncing team knowledge

  Or clone without syncing:
  npx @teamrc/cli clone trc_inv_a8f3c9e21b
```

#### Template updates

Add platform-awareness to templates. Some templates make more sense for certain platforms:
- "Full-Stack Product" → defaults to claude-code, cursor, copilot
- "Security Testing" → defaults to claude-code, codex
- Templates should suggest platforms, not enforce them

### 7.2 Dashboard: Multi-Team, Multi-Machine View

The dashboard currently shows machines and teams as flat lists. With multi-project teams, restructure to show the relationship between machines, projects, and teams.

#### New layout

```
┌─────────────────────────────────────────────────┐
│ Dashboard                          [Create team] │
│ Manage your machines and teams                   │
├─────────────────────────────────────────────────┤
│                                                  │
│ TEAMS (3)                                        │
│ ─────────────────────────────────────────────── │
│                                                  │
│ ▸ frontend-crew                    5 agents     │
│   Platforms: claude-code, cursor, copilot        │
│   Machines: my-laptop, work-vm                   │
│   Last sync: 3 minutes ago                       │
│                                                  │
│ ▸ backend-squad                    3 agents     │
│   Platforms: claude-code, codex                  │
│   Machines: my-laptop                            │
│   Last sync: 1 hour ago                          │
│                                                  │
│ ▸ my-assistants (global)           2 agents     │
│   Platforms: claude-code, openclaw               │
│   Machines: my-laptop                            │
│   Last sync: 12 minutes ago                      │
│                                                  │
│ MACHINES (2)                                     │
│ ─────────────────────────────────────────────── │
│                                                  │
│   my-laptop          trc_ak_abc...  just now     │
│     Global: my-assistants                        │
│     Projects:                                    │
│       ~/project-x → frontend-crew               │
│       ~/project-y → backend-squad                │
│                                    [Revoke ✕]   │
│                                                  │
│   work-vm            trc_ak_def...  5 min ago    │
│     Projects:                                    │
│       ~/project-x → frontend-crew               │
│                                    [Revoke ✕]   │
│                                                  │
└─────────────────────────────────────────────────┘
```

#### Team detail (expand)

Clicking a team row expands to show:
- Member list with roles
- Rules and skills count
- Invite code generation (inline)
- Sync log (recent activity)
- Platform breakdown (which platforms are active)

#### Data requirements

The relay needs to track:
- Which teams a token belongs to (already in `token_teams`)
- The scope per token-team association: `"global"` or `"project"`
- Project identifier per token-team (optional, e.g. repo name from git remote, or just the directory basename)

Add to `token_teams` table:
```elixir
add :scope, :string, default: "project"    # "global" or "project"
add :project_name, :string                  # optional, for dashboard display
```

The CLI sends `scope` and `project_name` in the join/sync request body.

### 7.3 Team Detail Page (new)

Add a dedicated page for viewing/editing a team: `/teams/:id`

#### View mode
- Team name, creation date
- Member list with roles
- Rules (id, body preview)
- Skills (id, description)
- Active machines and their sync status
- Sync log (scrollable, filterable)
- Invite section: generate new invite, show active invites

#### Edit mode (if team owner / account linked)
- Add/remove members inline (LiveView form)
- Edit rules and skills
- Changes push to all synced machines on save
- Rename team

This replaces the need to edit `.teamrc.yaml` manually for web-created teams. The CLI remains the primary interface, but the web provides a visual alternative.

### 7.4 Auth Verify Page (No Changes)

The device auth flow (`/auth/verify`) works correctly for multi-team. A machine can be linked to an account regardless of how many teams it belongs to.

### 7.5 Landing Page (new, optional)

Currently `/` redirects to `/new` or `/dashboard`. Consider a proper landing page:

- Hero: "Sync your AI agent teams across every platform"
- Platform logos: Claude Code, Cursor, Codex, Gemini, OpenClaw, Copilot, Amazon Q, Windsurf, Cline
- Quick start: `npx @teamrc/cli init`
- Feature highlights: multi-platform sync, team templates, live sync daemon
- Link to docs

This is low priority. The CLI is the primary entry point.

### 7.6 API Changes for Dashboard

#### New endpoint: `GET /api/account/teams`

Returns all teams for the authenticated account, with machine and project details:

```json
{
  "teams": [
    {
      "id": "uuid-123",
      "name": "frontend-crew",
      "members": [...],
      "machines": [
        {
          "token": "trc_ak_abc...",
          "name": "my-laptop",
          "scope": "project",
          "project_name": "project-x",
          "last_seen": "2026-03-07T12:00:00Z"
        }
      ]
    }
  ]
}
```

#### Updated endpoint: `POST /api/sync`

Add optional fields to sync request body:
```json
{
  "token": "trc_ak_...",
  "teamId": "uuid-123",
  "platform": "claude-code",
  "scope": "project",
  "project_name": "my-app",
  "hashes": {...}
}
```

### 7.7 Implementation Notes

- All new pages use LiveView (consistent with existing architecture)
- Team detail page can reuse components from the wizard (member list, rule editor, skill editor)
- Dashboard restructure is a LiveView template change. The data model (GenServer + Ecto) already has most of what's needed.
- Platform selection uses the same checkbox pattern as the wizard's rule/skill assignment
- No new JavaScript needed. LiveView handles all interactions.

---

## Phase 8: Security Review

### 8.1 YAML teamId injection

**Risk:** Cloned repo with malicious `.teamrc.yaml` containing attacker's teamId.

**Mitigation:** `teamrc sync` requires the machine's token to be registered with the team on the relay. An unregistered token gets 401. The attacker cannot force the victim to sync to their team; the victim must explicitly `teamrc join` first.

**Additional:** On first sync with a YAML-provided teamId that wasn't set by `init`/`join` on this machine, warn and require confirmation.

### 8.2 Platform whitelist

**Risk:** `platforms` field in YAML could contain arbitrary strings used in `getAdapter()`.

**Mitigation:** Validate against `VALID_PLATFORMS` constant in `readTeamYaml()`. Reject unknown platforms at parse time.

### 8.3 Relay URL trust

**Risk:** YAML `relay` field pointing to attacker's server to capture tokens/signatures.

**Mitigation:** Maintain `trustedRelays` list in global config. Auto-add relay on `init`/`join`. Prompt on first use of untrusted relay: "This project uses relay X. Trust? [y/N]".

### 8.4 OpenClaw namespace collision

**Risk:** Two teams with similar slugified names could collide.

**Mitigation:** Use first 8 chars of teamId (UUID) as namespace prefix: `trc-{teamId8}-{agent}`. Guarantees uniqueness.

### 8.5 `.github/` directory safety

**Risk:** Copilot adapter writing to `.github/` could interfere with workflows, CODEOWNERS, etc.

**Mitigation:** Only write to `.github/agents/` and `.github/instructions/`. All files prefixed `trc-`. Never touch other `.github/` subdirectories.

### 8.6 Global team scope escalation

**Risk:** A global team's agents are visible in ALL projects. A compromised global team could inject instructions into any project.

**Mitigation:** Document that global teams have broader trust scope. Project teams are preferred for shared/open-source work. `teamrc status` clearly shows which teams are active.

### 8.7 Concurrent daemons

**Risk:** Two daemons for different project teams on the same machine.

**Mitigation:** Each daemon reads its own `.teamrc.yaml` (or global config). Uses `teamId` in all relay requests. No shared state between daemons. A global team daemon and a project team daemon can run simultaneously without conflict.

### 8.8 Agent file overwrite between scopes

**Risk:** Global team has `trc-architect.md` in `~/.claude/agents/`. Project team also has `trc-architect.md` in `.claude/agents/`. Project wins (platform precedence), but global file still exists.

**Mitigation:** This is actually correct behavior. Platforms resolve project > global naturally. But `teamrc status` should warn about name shadows: "Agent 'architect' in project team shadows global team's 'architect'."

---

## Phase 9: Cleanup

### 9.1 Dead code removal

- `askScope()`: gone
- `primaryPlatform()`: gone
- Top-level `teamId`/`platform`/`noSync` in config: gone
- `requireClient()`: replaced by `requireTeamContext()`
- Single-platform daemon assumption: gone

### 9.2 Test updates

- Config tests: simplified global config + `globalTeam` field
- YAML tests: new fields (teamId, relay, platforms, noSync)
- New adapter tests: copilot, amazon-q, windsurf, cline, junie, continue, augment
- Integration: multi-platform apply, global vs project scope
- E2E: multi-team relay (one token, two teams)

### 9.3 Uninstall script update

Add all new platforms:
```bash
# Copilot
for f in .github/agents/trc-*.agent.md .github/instructions/trc-*.instructions.md; do
  remove_if_exists "$f"
done
# Amazon Q
for f in .amazonq/cli-agents/trc-*.json .amazonq/rules/trc-*.md; do ...
# Windsurf
for f in .windsurf/rules/trc-*.md .windsurf/workflows/trc-*.md; do ...
# Cline
for f in .clinerules/trc-*.md; do ...
# Junie
for d in .junie/skills/trc-*; do ...
# Continue
for f in .continue/rules/trc-*.md; do ...
# Augment
for f in .augment/rules/trc-*.md; do ...
```

---

## Phase 10: Rename `agent-team.yaml` → `.teamrc.yaml`

### Rationale

The project config file should follow dotfile conventions (like `.prettierrc`, `.eslintrc`) and match the project name. `.teamrc.yaml` is:
- A dotfile (conventional for config, hidden by default)
- Named after the project (`teamrc`)
- Explicitly `.yaml` for editor syntax highlighting and tooling
- Consistent with `~/.teamrc/` config directory

### 10.1 Backward compatibility

`readTeamYaml` callers use `resolveTeamYamlPath()` which checks `.teamrc.yaml` first, then falls back to `agent-team.yaml` with a deprecation warning. All writes go to `.teamrc.yaml`.

### 10.2 Files changed

| File | Change |
|------|--------|
| `cli/src/team-yaml.ts` | Export `TEAM_YAML`, `resolveTeamYamlPath()`. Error messages updated. |
| `cli/src/index.ts` | All reads via `resolveTeamYamlPath()`, all writes via `TEAM_YAML` constant |
| `cli/src/daemon.ts` | Watch path uses `resolveTeamYamlPath()` |
| `cli/src/config.ts` | Deprecation comments updated |
| `scripts/uninstall.sh` | Removes both `.teamrc.yaml` and `agent-team.yaml` |
| All test files | Filename references updated |
| `README.md` | Documentation updated |

### 10.3 Delete command

`teamrc delete` removes both `.teamrc.yaml` and legacy `agent-team.yaml` if present.

### 10.4 Migration path

Users with existing `agent-team.yaml` files:
1. CLI continues to work. Reads fall back to legacy filename.
2. Console prints deprecation warning each run
3. User renames file manually: `mv agent-team.yaml .teamrc.yaml`
4. Or `teamrc apply` / `teamrc init` / `teamrc join` writes `.teamrc.yaml` automatically

---

## Implementation Order

```
Phase 1: Config split + dual mode        ← DONE (config split, TeamContext, --global flag)
  ├── Phase 2: Relay multi-team          ← DONE (MapSet, team_id routing, BOLA)
  └── Phase 6: CLI UX overhaul          ← DONE (@clack/prompts, 17 commands, global flags)
Phase 3: Gemini rewrite                  ← DONE (native .gemini/agents/*.md with frontmatter)
Phase 4: OpenClaw rewrite               ← DONE (native .agents/agents/*.md, removed SOUL.md/workspaces)
Phase 5.1: Copilot adapter              ← NOT STARTED (stub only)
Phase 5.2: Amazon Q adapter             ← NOT STARTED (stub only)
Phase 5.3-5.7: Other adapters           ← NOT STARTED (stubs only)
Phase 7: Web UI                          ← DONE (team dashboard, member detail, guide, invites, catalog pickers)
Phase 8: Security hardening              ← DONE (33 audit items, input validation, IDOR protection)
Phase 9: Cleanup                         ← DONE (dead code, Rule→Skill unification, resolve-rules.ts removed)
Phase 10: Rename agent-team.yaml         ← DONE (.teamrc.yaml, backward compat removed)
```

Remaining work: Phase 5 new platform adapters (copilot, amazon-q, windsurf, cline, junie, continue, augment).

---

## Files Summary

### Modified
| File | Change |
|------|--------|
| `cli/src/config.ts` | Simplified config, `globalTeam`, expanded detection |
| `cli/src/adapters/base.ts` | Extended `TeamDefinition`, new platform registry |
| `cli/src/team-yaml.ts` | New fields: teamId, relay, platforms, noSync |
| `cli/src/index.ts` | `requireTeamContext()`, `--global` flag, multi-platform apply |
| `cli/src/daemon.ts` | Read teamId from YAML or global config |
| `cli/src/client.ts` | Add teamId to sync/push request bodies |
| `cli/src/adapters/gemini.ts` | Full rewrite to native agent files |
| `cli/src/adapters/openclaw.ts` | Team-namespaced workspaces |
| `teamrc/lib/teamrc/teams.ex` | Multi-team per token |
| `teamrc/lib/teamrc_web/controllers/api_controller.ex` | teamId in request routing |
| `scripts/uninstall.sh` | New platform cleanup |

### Created
| File | Description |
|------|-------------|
| `cli/src/adapters/copilot.ts` | GitHub Copilot adapter |
| `cli/src/adapters/amazon-q.ts` | Amazon Q Developer adapter |
| `cli/src/adapters/windsurf.ts` | Windsurf adapter (rules/workflows) |
| `cli/src/adapters/cline.ts` | Cline adapter (rules) |
| `cli/src/adapters/junie.ts` | JetBrains Junie adapter (guidelines/skills) |
| `cli/src/adapters/continue.ts` | Continue.dev adapter (rules) |
| `cli/src/adapters/augment.ts` | Augment Code adapter (rules) |
| Tests for each new adapter | |

### Deleted
| What | Why |
|------|-----|
| `askScope()` | Replaced by `--global` flag |
| `primaryPlatform()` | Replaced by platforms array |
| `requireClient()` | Replaced by `requireTeamContext()` |
| Top-level teamId/platform/noSync in config | Moved to YAML or `globalTeam` |
