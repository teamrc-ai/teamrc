# Task System: Cross-Platform Agent Task Assignment

**Date:** 2026-03-15
**Status:** Proposed
**Scope:** Task file format, daemon task spawning, CLI commands

---

## Problem

Agents on a teamrc team can share knowledge but cannot assign work to each other. A Claude Code agent that identifies a copywriting task has no way to hand it off to the OpenClaw copywriter agent -- it can only leave a note in the knowledge file and hope someone picks it up next session.

### What we want

1. Any agent can create a task and assign it to a team member
2. The task syncs to the machine where that member runs
3. The daemon on that machine spawns the appropriate CLI agent to execute the task
4. The agent completes the work, marks the task done, and the result syncs back
5. The originating agent (or human) sees the completed task

---

## Architecture

### Task file

`.teamrc/tasks-<slug>.md` -- one file per team, same pattern as knowledge.

```markdown
# Tasks

## TODO

- #1 [copywriter] Write landing page hero copy based on positioning in knowledge file
- #2 [seo-specialist] Audit meta tags on /guide and /new pages

## IN PROGRESS

- #3 [analytics-lead] Set up conversion funnel tracking (claimed 2026-03-15T14:30:00Z)

## DONE

- #4 [copywriter] Draft brand voice examples for error messages (completed 2026-03-15T12:00:00Z)
```

**Format per task line:** `- #<id> [<member-name>] <description> (<status metadata>)`

IDs are auto-incrementing integers, assigned locally. Collisions across machines are possible but harmless -- the relay deduplicates by content hash on merge.

### Agent instructions

A `team-tasks` skill (`alwaysApply: true`) tells agents how to interact with the task file:

```
At session start, read `.teamrc/tasks-<slug>.md`.
- If there are TODO tasks assigned to you (your member name in brackets), claim one by moving it to IN PROGRESS with a timestamp.
- When you complete a task, move it to DONE with a completion timestamp.
- To assign a task to a teammate, append it to TODO with their member name.
- Work on one task at a time. Do not claim multiple tasks.
```

This skill is delivered to agents via the same `alwaysApply` mechanism as `team-knowledge` -- native rules on Claude Code/Cursor, inlined in agent files on Codex/Gemini/OpenClaw.

### Daemon task watching

The daemon already watches `.teamrc/` for knowledge file changes. Extend it to also watch the tasks file:

```typescript
// In daemon.ts
const taskPath = path.join('.teamrc', `tasks-${teamSlug}.md`);
watcher.add(taskPath);

watcher.on('change', (filePath) => {
  if (filePath === taskPath) {
    handleTaskChange(filePath);
  }
});
```

### Sync

Tasks sync using the same mechanism as knowledge:

- **WebSocket channel**: Add a `tasks:push` event to the existing knowledge channel (or a new `tasks:<team_id>` topic)
- **Merge**: Line-based merge, same as knowledge. Tasks move between sections (TODO → IN PROGRESS → DONE) which is a delete+add, not a conflict
- **Anti-echo**: Same `lastWrittenHash` pattern as knowledge

A separate channel topic (`tasks:<team_id>`) is cleaner than overloading the knowledge channel, since task updates trigger different daemon behavior (potential agent spawning).

### Agent spawning

When the daemon receives a task update and detects a new TODO task assigned to a member that runs on this machine:

```typescript
interface SpawnConfig {
  platform: string;        // "claude-code" | "codex" | "gemini" | "openclaw"
  memberName: string;      // maps to agent file
  projectDir: string;      // cwd for the spawned process
  timeoutMs: number;       // max runtime, default 10 minutes
  autoSpawn: boolean;      // user opt-in required
}

function spawnAgent(task: Task, config: SpawnConfig): ChildProcess {
  const prompt = `You have a new task assigned to you. Read .teamrc/tasks-${teamSlug}.md and complete task #${task.id}: "${task.description}". When done, mark it complete in the tasks file.`;

  switch (config.platform) {
    case 'claude-code':
      return spawn('claude', ['-p', prompt, '--allowedTools', 'Read,Write,Edit,Bash,Glob,Grep'], {
        cwd: config.projectDir,
        timeout: config.timeoutMs,
      });
    case 'codex':
      return spawn('codex', [prompt], {
        cwd: config.projectDir,
        timeout: config.timeoutMs,
      });
    case 'gemini':
      return spawn('gemini', [prompt], {
        cwd: config.projectDir,
        timeout: config.timeoutMs,
      });
    case 'openclaw':
      return spawn('openhands', ['-p', prompt], {
        cwd: config.projectDir,
        timeout: config.timeoutMs,
      });
  }
}
```

**Lifecycle:**
1. Daemon detects new task for local member
2. Spawns agent as child process
3. Sets timeout (default 10 minutes)
4. On exit: daemon detects task file changes, syncs results
5. On timeout: kill process, mark task as `FAILED (timeout)` in file

**Concurrency limit:** One spawned agent at a time per daemon. Queue additional tasks. Prevents resource exhaustion and conflicting file edits.

### Member-to-machine mapping

The daemon knows which platforms are configured on this machine (from `.teamrc.yaml` `platforms:` field). But it doesn't know which member maps to which platform on which machine.

**Option A: Convention-based.** If this machine has `claude-code` in its platforms list and the task is for `@copywriter`, the daemon spawns Claude Code with the copywriter's agent file. Works for single-machine teams.

**Option B: Explicit mapping in `.teamrc.yaml`.**

```yaml
members:
  - name: copywriter
    role: Copywriter
    platform: openclaw    # ← which platform runs this member
```

The daemon only spawns tasks for members whose `platform` matches one of this machine's configured platforms. Tasks for other members are ignored (they'll be handled by another machine's daemon).

**Option C: Machine-level claim.** Each daemon registers its token + platforms with the relay. The relay routes tasks to the right daemon based on which machine has the right platform. Most sophisticated, requires relay changes.

**Recommendation:** Start with Option A for v1 (single-machine teams). Add Option B when multi-machine becomes common.

---

## CLI Commands

### `teamrc task create`

```bash
teamrc task create "Write landing page copy" --assign copywriter
```

Appends to the TODO section of the tasks file. Daemon syncs automatically.

### `teamrc task list`

```bash
teamrc task list
teamrc task list --status todo
teamrc task list --assign copywriter
```

Reads and displays the tasks file with formatting.

### `teamrc task done <id>`

```bash
teamrc task done 3
```

Moves task #3 to DONE. Convenience command for humans.

---

## Daemon Configuration

Auto-spawning agents is opt-in. New fields in the daemon config:

```yaml
# .teamrc.yaml
daemon:
  autoSpawn: true           # default: false
  spawnTimeout: 600000      # ms, default: 10 min
  maxConcurrent: 1          # default: 1
```

When `autoSpawn: false` (default), the daemon syncs the task file but does not spawn agents. Tasks are picked up manually when agents start their next session. This is the safe default -- agents reading the file and claiming tasks on session start still works without auto-spawn.

---

## Safety

### Headless agent permissions

Each platform handles permissions differently:

- **Claude Code**: Requires `--dangerously-skip-permissions` or an allowlist via `--allowedTools`. For daemon-spawned agents, recommend an explicit allowlist scoped to the project directory.
- **Codex**: Has a `--full-auto` flag for non-interactive mode. Sandbox enabled by default.
- **Gemini**: TBD -- check if headless mode exists.
- **OpenClaw**: Supports headless execution natively.

### Resource limits

- **Timeout**: Hard kill after configurable timeout (default 10 min)
- **Concurrency**: One agent at a time per daemon (queue overflow tasks)
- **Cost**: No built-in cost cap -- relies on platform-level spending limits (Anthropic, OpenAI dashboards)

### Task validation

- Max task description length: 1000 characters
- Max tasks in file: 200 (older DONE tasks pruned, same FIFO as knowledge)
- Member name must match a member in `.teamrc.yaml`

---

## Implementation

### Phase 1: Task file + skill

- Add `createTeamTasksSkill()` to `base.ts` (same pattern as `createTeamKnowledgeSkill`)
- Add task file creation to `init` and `join` commands
- Add task file path methods to each adapter (`getTasksPath()`)
- Write the `team-tasks` alwaysApply skill with instructions for reading/writing tasks
- Task file CRUD helpers: `parseTasks()`, `addTask()`, `claimTask()`, `completeTask()`

### Phase 2: Task sync via daemon

- Add tasks file to daemon's chokidar watch list
- Add `tasks:<team_id>` channel topic (or extend knowledge channel)
- Add `tasks:push` and `tasks:updated` events
- Server-side: `update_tasks/3` in teams.ex (merge, persist, broadcast)
- Anti-echo for tasks file (same pattern as knowledge)

### Phase 3: CLI commands

- `teamrc task create` -- append to TODO section
- `teamrc task list` -- display tasks with status filtering
- `teamrc task done <id>` -- move task to DONE

### Phase 4: Agent spawning

- Add `SpawnManager` to daemon (queue, concurrency limit, timeout)
- Platform-specific spawn commands (claude, codex, gemini, openhands)
- `autoSpawn` config in `.teamrc.yaml`
- Spawn on incoming task for local member
- Process lifecycle management (exit, timeout, error)

### Phase 5: Multi-machine routing (future)

- Member-to-platform mapping in `.teamrc.yaml`
- Daemon only spawns for members matching local platforms
- Relay-side task routing (optional, for Option C)

---

## Decisions

| Decision | Rationale |
|----------|-----------|
| Markdown task file | Agents already know how to read/write markdown. Same pattern as knowledge. No new format to learn. |
| `alwaysApply` skill for instructions | Proven delivery mechanism. Already fixed to work across all 5 platforms. |
| File-based sync (not API-first) | Reuses existing daemon infrastructure. Agents write files naturally. API layer can be added later for atomic operations. |
| One agent at a time | Prevents conflicting file edits. Simple queue model. Revisit if parallelism is needed. |
| Auto-spawn opt-in | Headless agents writing code is powerful but risky. Default to safe (session-based pickup). |
| Separate channel topic for tasks | Task updates trigger different daemon behavior (spawning) than knowledge updates. Clean separation of concerns. |
| FIFO pruning for DONE tasks | Same pattern as knowledge. Old completed tasks are least useful. Keep file size bounded. |

---

## Out of Scope

- Task dependencies (task B blocked by task A)
- Task priorities / ordering
- Task comments / threaded discussion
- Task templates
- Web UI for task management
- Cross-team task assignment
- Cost tracking per task
- Agent output capture / task result storage (beyond what the agent writes to files)
- Retry failed tasks automatically
