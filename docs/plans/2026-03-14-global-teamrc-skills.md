# Global teamrc Skills (On-Demand Slash Commands)

**Date:** 2026-03-14
**Status:** Proposed
**Depends on:** [Knowledge Daemon](./2026-03-14-knowledge-daemon.md) (Phase 1 pruning is complete, Phases 2-4 in progress)

---

## Problem

teamrc installs `alwaysApply` rules and per-agent skills, but ships no **on-demand skills**  --  slash commands users can invoke mid-session. This is a missed opportunity: both Claude Code and Cursor support the [Agent Skills](https://agentskills.io) open standard, and Cursor even auto-discovers skills from `.claude/skills/` and `.agents/skills/` for cross-platform compatibility.

Users currently have no way to interact with teamrc from inside their coding session. Want to save a finding? Hope the agent remembers the "append to knowledge file" instruction. Want to see what the team knows? Open the file manually. Want to check knowledge size (relevant now with the 100KB cap and FIFO pruning)? Run `teamrc status` in a separate terminal.

### Platform support for on-demand skills

| Platform | Skills directory | Slash commands | Auto-discovery |
|---|---|---|---|
| **Claude Code** | `.claude/skills/` | `/skill-name` | Yes  --  descriptions loaded, full content on invoke |
| **Cursor** | `.cursor/skills/`, `.agents/skills/` | `/skill-name` | Yes  --  also reads `.claude/skills/`, `.codex/skills/` |
| **Gemini** | `.agents/skills/` | Likely | Likely |
| **Codex** | No native support | No | No |
| **OpenClaw** | `~/.openclaw/skills/` | No user invocation | Agent-discoverable only |

Claude Code and Cursor are the primary targets. Codex and OpenClaw get the skills written to disk (no harm) but users can't invoke them.

### Relevant SKILL.md frontmatter

Both Claude Code and Cursor support these fields:

| Field | Purpose |
|---|---|
| `name` | Becomes the `/slash-command` |
| `description` | Agent uses this to decide when to auto-invoke |
| `disable-model-invocation` | `true` = user-only, agent can't auto-trigger |
| `user-invocable` | `false` = agent-only, hidden from `/` menu (Claude Code only) |
| `allowed-tools` | Restrict tool access when skill is active |
| `context` | `fork` to run in a subagent |
| `argument-hint` | Autocomplete hint (e.g., `[topic]`) |

---

## Proposed Skills

### 1. `/trc-save-finding`  --  Save a finding to team knowledge

**Why:** The `team-knowledge` alwaysApply rule tells agents to "append useful findings before finishing." But agents often skip this, and users have no way to explicitly trigger it. This skill gives users a direct slash command to save something mid-session.

**Behavior:**
1. Takes a topic and description as arguments
2. Reads the current knowledge file
3. Appends a `## <topic>` section with the description (3-5 lines)
4. Writes the updated file
5. If daemon is running, the file change auto-syncs to relay
6. If content exceeds cap, runs prune (oldest sections dropped)
7. Reports current knowledge size

**Frontmatter:**
```yaml
---
name: trc-save-finding
description: Save a finding or decision to the team knowledge file so other team members and future sessions can benefit from it.
argument-hint: <topic> <details>
disable-model-invocation: true
---
```

`disable-model-invocation: true` because we don't want agents auto-triggering this  --  the alwaysApply rule already handles the "agent saves findings" use case. This is for users who want to explicitly save something.

**Body:**
```markdown
Save the following finding to the team knowledge file.

1. Read the knowledge file at `$KNOWLEDGE_PATH`
2. Append a new section:
   ```
   ## $ARGUMENTS[0]
   $ARGUMENTS[1:]
   ```
3. If the topic already exists as a heading, append to that section instead of creating a duplicate
4. Write the updated file
5. Report the current file size and how close it is to the 100KB relay cap
```

### 2. `/trc-knowledge`  --  Read team knowledge

**Why:** Users want to see what the team knows without opening the file. Especially useful when onboarding to a project or checking if a topic has already been documented.

**Behavior:**
1. Reads the knowledge file
2. Displays a summary: section count, total size, size relative to 100KB cap
3. Lists all `## ` headings with a one-line preview
4. If arguments provided, searches for relevant sections and displays full content

**Frontmatter:**
```yaml
---
name: trc-knowledge
description: Display team knowledge contents and status. Shows section headings, size info, and can search for specific topics. Use when you need to check what the team has documented.
argument-hint: "[search-term]"
disable-model-invocation: false
---
```

`disable-model-invocation: false`  --  agents SHOULD auto-trigger this when they need to check team context. This complements the alwaysApply rule which loads the content at session start  --  this skill lets the agent refresh mid-session.

### 3. `/trc-status`  --  Show team and knowledge status

**Why:** Quick reference for current team state without leaving the editor. Shows team name, members, skills, knowledge size, and daemon status.

**Frontmatter:**
```yaml
---
name: trc-status
description: Show current teamrc team status including members, skills, knowledge size, and sync status.
disable-model-invocation: true
---
```

**Body:**
```markdown
Show the current teamrc team status:

1. Read `.teamrc.yaml` and display:
   - Team name and ID
   - Members (name, role)
   - Skills (name, alwaysApply status)
2. Read the knowledge file and display:
   - File path
   - Total size and percentage of 100KB cap
   - Number of sections
   - Preamble size
3. If size > 70% of cap, warn that oldest sections will be pruned on next sync
4. If size > 90% of cap, warn urgently
```

### 4. `/trc-switch-team`  --  Switch active team (FUTURE)

**Why:** When multi-team-per-project is supported, users will need to switch context. Not implemented now  --  placeholder for when the feature exists.

**Frontmatter (future):**
```yaml
---
name: trc-switch-team
description: Switch the active teamrc team in this project. Lists available teams if no argument provided.
argument-hint: "[team-name]"
disable-model-invocation: true
---
```

---

## Interaction with Knowledge Daemon

The knowledge daemon plan introduces real-time sync via Phoenix Channels. The skills interact with it naturally:

| Skill | Daemon running | Daemon not running |
|---|---|---|
| `/trc-save-finding` | Writes to file → chokidar detects → daemon pushes via channel → other machines get it in <1s | Writes to file → user must `teamrc push` manually |
| `/trc-knowledge` | Reads local file (always up-to-date via daemon) | Reads local file (may be stale) |
| `/trc-status` | Could query daemon for sync status, connection state, last sync time | Shows file-only status |

The skills don't need to know about the daemon  --  they just read/write the knowledge file. The daemon handles sync transparently.

### Pruning interaction

`/trc-save-finding` should call `pruneKnowledge()` after appending, same as every other knowledge write path (push, pull, sync, daemon). This is already the pattern established in the knowledge daemon plan: "pruning happens wherever knowledge is merged."

---

## Implementation

### Phase 1: Skill writing infrastructure

Update adapters to write on-demand skills with correct frontmatter.

**Current state:** `writeSkillsAsNativeFiles()` writes on-demand skills to `skills/` dirs but only includes `name`, `title`, and `description` in frontmatter. Missing: `disable-model-invocation`, `user-invocable`, `argument-hint`, `allowed-tools`, `context`.

**Changes to `cli/src/adapters/base.ts`:**
- Add optional fields to `Skill` interface:
  ```typescript
  interface Skill {
    id: string;
    title?: string;
    description?: string;
    alwaysApply?: boolean;
    globs?: string[];
    userInvocable?: boolean;
    disableModelInvocation?: boolean;
    argumentHint?: string;
    allowedTools?: string[];
    context?: "fork";
    body: string | { source: string };
  }
  ```
- Update `writeSkillDir()` to include new frontmatter fields

**Changes to each adapter's skill writing:**
- Claude Code: `writeSkillsAsNativeFiles()`  --  write new frontmatter fields to `SKILL.md`
- Cursor: `writeSkillAsMdc()`  --  on-demand skills go to `.cursor/skills/`, write new frontmatter. Note: Cursor also discovers from `.agents/skills/` and `.claude/skills/`
- Codex: No change  --  Codex doesn't support on-demand skills natively
- Gemini: Write to `.agents/skills/` with new frontmatter
- OpenClaw: Write to `~/.openclaw/skills/` with new frontmatter

**Changes to `cli/src/team-yaml.ts`:**
- Parse/serialize new Skill fields from `.teamrc.yaml`

### Phase 2: Built-in teamrc skills

Create the three skills as built-in skills that get installed with every team (like `team-knowledge` but on-demand instead of alwaysApply).

**Add to `cli/src/adapters/base.ts`:**
```typescript
export function createBuiltInSkills(knowledgePath: string): Skill[] {
  return [
    {
      id: "trc-save-finding",
      title: "Save Finding",
      description: "Save a finding or decision to the team knowledge file",
      disableModelInvocation: true,
      argumentHint: "<topic> <details>",
      body: `Save the finding to the team knowledge file at \`${knowledgePath}\`.

1. Read the current knowledge file
2. Append a new \`## <topic>\` section with the provided details (3-5 lines)
3. If the topic already exists as a heading, append to that section
4. Write the updated file
5. Report the current file size relative to the 100KB relay cap
6. If size > 90%, warn that oldest sections will be pruned on next sync`,
    },
    {
      id: "trc-knowledge",
      title: "Team Knowledge",
      description: "Display team knowledge contents, search for topics, and show size status",
      argumentHint: "[search-term]",
      body: `Read and display the team knowledge file at \`${knowledgePath}\`.

1. Read the file and parse into preamble + sections
2. Display summary: section count, total size, percentage of 100KB cap
3. List all ## headings with first-line preview
4. If arguments provided, search sections and display matching content in full
5. If size > 70%, note that oldest sections will be pruned when cap is reached`,
    },
    {
      id: "trc-status",
      title: "Team Status",
      description: "Show current teamrc team status including members, skills, and knowledge size",
      disableModelInvocation: true,
      body: `Show the current teamrc team status.

1. Read \`.teamrc.yaml\` and display team name, members (name + role), and skills
2. Read the knowledge file at \`${knowledgePath}\` and display size info
3. If knowledge > 70% of 100KB cap, warn about upcoming pruning
4. If knowledge > 90%, warn urgently`,
    },
  ];
}
```

**Key decision:** These are NOT added to `.teamrc.yaml`. They are built-in skills that adapters inject at write time, similar to how `enrichTeamKnowledgeSkill` works. Users don't see them in their YAML and can't remove them (they're infrastructure, not team config). If a user doesn't want them, they can set `disable-model-invocation: true` to hide from agent auto-triggering, or use platform-level permission rules to block them.

Alternative: Add them to `.teamrc.yaml` like `team-knowledge`. Pro: visible, removable. Con: clutters YAML with 3 more skills users didn't ask for.

**Recommendation:** Start with built-in (injected at write time). Move to YAML-persisted if users want to customize them.

### Phase 3: Adapter integration

Each adapter's `writeTeam()` calls `createBuiltInSkills(knowledgePath)` and writes them to the appropriate skills directory.

**Claude Code:** Write to `.claude/skills/trc-save-finding/SKILL.md`, etc.
**Cursor:** Write to `.cursor/skills/trc-save-finding/SKILL.md` (Cursor also discovers from `.agents/skills/`)
**Gemini:** Write to `.agents/skills/trc-save-finding/SKILL.md`
**Codex:** Skip  --  no native skill support
**OpenClaw:** Write to `~/.openclaw/skills/trc-save-finding/SKILL.md`

### Phase 4: `/trc-switch-team` (FUTURE)

Depends on multi-team-per-project support. When implemented:
- Lists available teams from `.teamrc.yaml` (if multi-team) or workspace
- Switches active team context
- Re-runs `teamrc apply` for the selected team
- Updates daemon connection if running

---

## Cleanup: Remove per-agent skill body inlining

While implementing this, also fix the redundant per-agent skill inlining identified in the skills audit:

1. **Claude Code**: Remove body inlining in `buildAgentFile()` (lines 424-431). Keep `skills:` frontmatter reference  --  that's how Claude Code knows which skills the agent can use.
2. **Cursor**: Remove body inlining in `writeAgentMd()` (lines 228-243). Cursor auto-discovers skills, no per-agent reference needed.
3. **Codex**: Keep body inlining  --  Codex has no native skill support, inlining is the only way.
4. **Gemini**: Remove body inlining in `buildAgentFile()` (lines 373-382). Gemini reads from `.agents/skills/`.
5. **OpenClaw**: Already minimal  --  just lists title+description, not full body. Keep as-is.

Also fix the broken frontmatter reference bug in Claude Code: `resolveAgentSkills()` returns alwaysApply skills, which get listed in agent frontmatter `skills:` pointing to `.claude/skills/`  --  but alwaysApply skills are in `.claude/rules/`. Filter alwaysApply/glob skills out of the frontmatter list.

---

## Files to modify

### Phase 1 (skill writing infrastructure)
1. `cli/src/adapters/base.ts`  --  Extend `Skill` interface, update `writeSkillDir()`
2. `cli/src/team-yaml.ts`  --  Parse/serialize new fields

### Phase 2 (built-in skills)
3. `cli/src/adapters/base.ts`  --  Add `createBuiltInSkills()`

### Phase 3 (adapter integration)
4. `cli/src/adapters/claude-code.ts`  --  Write built-in skills, fix frontmatter bug, remove body inlining
5. `cli/src/adapters/cursor.ts`  --  Write built-in skills, remove body inlining
6. `cli/src/adapters/codex.ts`  --  Skip built-in skills (no native support)
7. `cli/src/adapters/gemini.ts`  --  Write built-in skills, remove body inlining
8. `cli/src/adapters/openclaw.ts`  --  Write built-in skills

### Tests
9. `cli/src/__tests__/claude-code-rules.test.ts`  --  Test built-in skill writing, frontmatter fields
10. `cli/src/__tests__/cursor-rules.test.ts`  --  Test built-in skill writing
11. `cli/src/__tests__/gemini-rules.test.ts`  --  Test built-in skill writing
12. `cli/src/__tests__/openclaw-rules.test.ts`  --  Test built-in skill writing

---

## Decisions

| Decision | Rationale |
|---|---|
| `disable-model-invocation: true` for save-finding | Agents already have the alwaysApply rule for auto-saving. The slash command is for explicit user control. |
| `disable-model-invocation: false` for knowledge | Agents should be able to refresh knowledge mid-session. Complements the alwaysApply rule that loads at start. |
| Built-in skills (not YAML-persisted) | Keeps `.teamrc.yaml` clean. These are platform infrastructure, not team config. |
| No skill for knowledge pruning | Pruning is automatic (daemon plan). Users don't need to trigger it manually. |
| `/trc-` prefix for all skills | Avoids collision with user skills. Consistent with `trc-` prefix used for rules and agent files. |
| Skip Codex for built-in skills | Codex has no native skill/slash-command system. Writing SKILL.md files would be dead weight. |

---

## Out of Scope

- `/trc-switch-team` implementation (future, needs multi-team-per-project)
- `/trc-sync` slash command (use CLI `teamrc sync`  --  syncing is an admin action, not a mid-session action)
- Script-based skills (all three skills are prompt-based, no `scripts/` directory needed)
- Cursor `.cursor/commands/` migration (Cursor's `/migrate-to-skills` handles this)
- Web UI for managing built-in skills
- `context: fork` execution (skills run inline, no subagent needed)
