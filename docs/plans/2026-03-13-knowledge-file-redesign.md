# Knowledge File Redesign

**Date:** 2026-03-13
**Status:** Proposed
**Scope:** CLI adapters, knowledge storage paths, LLM instruction text, team name generation

---

## Problem

Team knowledge  --  a shared markdown file where LLM agents record findings for cross-session and cross-machine continuity  --  has three bugs:

### 1. Inconsistent paths across platforms

| Platform | Actual read/write path | Instruction tells agents |
|----------|----------------------|-------------------------|
| Claude Code | `{cwd}/teamrc-knowledge.md` | `.claude/teamrc-knowledge.md` |
| Cursor | `{cwd}/teamrc-knowledge.md` | `teamrc-knowledge.md` |
| Codex | `{cwd}/teamrc-knowledge.md` | `teamrc-knowledge.md` |
| Gemini | `{cwd}/teamrc-knowledge.md` | `teamrc-knowledge.md` |
| OpenClaw | `~/.openclaw/teamrc-knowledge.md` | `~/.openclaw/teamrc-knowledge.md` |

Claude Code has a live bug: the instruction references `.claude/teamrc-knowledge.md` but the code reads/writes at project root. Agents are directed to a nonexistent file.

### 2. No team isolation

All teams in a project write to the same `teamrc-knowledge.md`. With multi-team support shipped, two teams on one repo get knowledge collision.

### 3. Polluted project root

`teamrc-knowledge.md` sits alongside source code. The `.teamrc/` directory already exists (holds `sync-state.json`), is gitignored by `init`, and is the natural home for teamrc artifacts.

### 4. Codex subagent gap

Codex subagent TOML files have no knowledge instruction at all  --  only the AGENTS.md routing file does.

### 5. LLM write compliance is low

The current instruction ("when you discover something important") is vague. LLMs rarely self-interrupt to write knowledge. No format guidance leads to unstructured noise.

---

## Solution

### New path convention

| Scope | Path |
|-------|------|
| Project | `.teamrc/knowledge-<team-slug>.md` |
| Global | `~/.teamrc/knowledge-<team-slug>.md` |
| OpenClaw (global-only) | `~/.openclaw/knowledge-<team-slug>.md` |

OpenClaw keeps its own directory because its entire state (agents, skills, config) lives in `~/.openclaw/`. Moving just knowledge to `~/.teamrc/` would scatter state.

### Heroku-style team names

On `teamrc init` and web team creation, append a random suffix to team names: `product-team-coral-9f`, `infra-squad-pine-3a`. This makes slugs unique by default, eliminating collision concerns for knowledge filenames, agent file prefixes, and relay identification.

Generation: `<user-chosen-name>-<word>-<hex>` where word is from a curated ~100 word list (colors, animals, materials) and hex is 2 random bytes. The suffix is appended at creation time only  --  users can still rename if they want.

### Improved LLM instructions

**Orchestrator** (CLAUDE.md, AGENTS.md, GEMINI.md)  --  read-awareness, delegates writes to subagents:

```markdown
### Team Knowledge

This team (<team-name>) shares a knowledge file at `<path>`.
Read this file at the start of every session for context from prior work.
Subagents will also read and write to this file.
```

**Subagents** (per-agent `.md` files)  --  read + write with task-boundary triggers:

```markdown
## Team Knowledge

Before starting work, read `<path>` for shared context.
Before finishing, append any useful findings as a `## <topic>` entry (3-5 lines).
Do not delete existing entries.
```

Key improvements over current text:
- **Task-boundary triggers** ("before starting" / "before finishing") replace vague "when you discover something important"
- **Lightweight format** (`## <topic>`, 3-5 lines) prevents noise while keeping write friction low
- **Append-only rule** prevents accidental deletion
- **One template across all platforms**  --  only the path varies
- **Orchestrator doesn't write**  --  reduces duplicate entries from orchestrator summarizing what subagents already wrote

### No shared cross-team knowledge

Each team's knowledge is isolated. A project with two teams gets two separate files. This matches the existing principle that skills and rules are explicitly assigned, not inherited. Cross-team knowledge sharing is out of scope  --  revisit if user demand emerges.

---

## Architecture

### Knowledge path resolution

Add to `base.ts`:

```typescript
export function knowledgeFileName(teamSlug: string): string {
  return `knowledge-${teamSlug || "team"}.md`;
}
```

The slug comes from `slugify(team.name)` which already exists in `base.ts`. With Heroku-style names, the slug is globally unique.

### Adapter changes

Add `teamSlug` as an optional constructor parameter to all 5 adapters (default: `"team"`). Update `getAdapter` signature:

```typescript
export function getAdapter(platform: string, teamSlug?: string): PlatformAdapter
```

Each adapter's `knowledgePath()` changes to use the new convention:

| Adapter | Project path | Global path |
|---------|-------------|-------------|
| claude-code | `.teamrc/knowledge-<slug>.md` | `~/.teamrc/knowledge-<slug>.md` |
| cursor | `.teamrc/knowledge-<slug>.md` | N/A |
| codex | `.teamrc/knowledge-<slug>.md` | N/A |
| gemini | `.teamrc/knowledge-<slug>.md` | `~/.teamrc/knowledge-<slug>.md` |
| openclaw | N/A | `~/.openclaw/knowledge-<slug>.md` |

`writeKnowledge()` must `mkdirSync(.teamrc/, { recursive: true })` before writing. Claude Code and OpenClaw already do this for their current dirs.

`uninstall()` deletes both new-path and legacy-path files for clean upgrades.

### Call site changes

~12 `getAdapter()` call sites need to pass the team slug. The slug is available from `team.name` via `slugify()` in all primary commands (init, join, sync, push, pull, apply, add-member, daemon).

Four commands don't have team context at the point they call `getAdapter` (import, status, doctor, delete). These use the default `"team"` fallback, which is safe because:
- `import` and `doctor` don't call knowledge methods
- `status` reads but won't find `knowledge-team.md` (returns `""`, acceptable)
- `delete`'s `uninstall()` should glob-delete `knowledge-*.md` instead of targeting a specific slug

### Relay protocol

**No changes.** Knowledge syncs as an opaque string via `client.pushTeam(team, knowledge)` and `client.getTeam()`. The relay stores the raw content. The file path is entirely a local adapter concern.

`mergeKnowledge()` in `team-yaml.ts` operates on strings, not paths. `computeKnowledgeHash()` hashes content. Neither cares about file location.

### Team rename handling

If a team is renamed, the slug changes and the old knowledge file becomes orphaned. `teamrc apply` should detect this: if `knowledge-<old-slug>.md` exists but `knowledge-<new-slug>.md` doesn't, rename the file. With Heroku-style names, renames should be rare since the name is auto-generated and unique.

---

## Heroku-Style Name Generation

### Format

```
<base-name>-<word>-<hex>
```

- `<base-name>`: User-chosen name or template default (e.g., `product-team`, `backend-squad`)
- `<word>`: Random word from a curated list (~100 words: colors, animals, materials  --  e.g., `coral`, `falcon`, `cedar`, `slate`)
- `<hex>`: 2 random bytes as hex (4 chars), e.g., `9f3a`

Examples: `product-team-coral-9f3a`, `infra-squad-cedar-2b71`, `frontend-dev-falcon-e4a0`

### Where it applies

- `teamrc init`  --  when creating a new team (append suffix to the chosen/template name)
- Web wizard (`/new`)  --  same generation logic server-side
- Template catalog teams  --  base name comes from template, suffix added on instantiation

### Where it does NOT apply

- `teamrc join` / `teamrc clone`  --  team already has a name from the relay
- Team renames  --  user explicitly chooses the new name

### Implementation

A small utility function in `base.ts` or a new `names.ts`:

```typescript
const WORDS = ["coral", "falcon", "cedar", "slate", "ember", ...]; // ~100 words

export function generateTeamSuffix(): string {
  const word = WORDS[Math.floor(Math.random() * WORDS.length)];
  const hex = crypto.randomBytes(2).toString("hex");
  return `${word}-${hex}`;
}

export function generateTeamName(baseName: string): string {
  return `${slugify(baseName)}-${generateTeamSuffix()}`;
}
```

---

## Build Sequence

### Phase 1: Name generation utility
- Add word list and `generateTeamSuffix()` / `generateTeamName()` to CLI
- Wire into `teamrc init` and web wizard team creation
- Tests for uniqueness, format, slug safety

### Phase 2: Knowledge path utility (no behavior change)
- Add `knowledgeFileName(teamSlug)` to `base.ts`
- Update `getAdapter` signature to accept `teamSlug`
- Pass `teamSlug` through to adapter constructors (constructors store but don't use it yet)
- All existing tests pass  --  no path changes

### Phase 3: Adapter path migration
- Update `knowledgePath()` in all 5 adapters to new `.teamrc/` convention
- Update `writeKnowledge()` to create `.teamrc/` directory
- Update `uninstall()` to delete both new and legacy paths
- Add knowledge instruction to Codex subagent TOML files (fixing the gap)

### Phase 4: Instruction text updates
- Update all `buildAgentFile()` / `buildClaudeMdSection()` / `writeAgentsMd()` templates
- Differentiate orchestrator (read-awareness) vs subagent (read+write) instructions
- Standardize one template, vary only the path

### Phase 5: Thread slug through call sites
- Update ~12 `getAdapter()` calls in commands and daemon to pass `slugify(team.name)`
- Handle `delete` command with glob-based cleanup
- Full test suite: `cd cli && npm test`

### Phase 6: Rename detection
- In `teamrc apply`, detect old-slug knowledge file and rename to new-slug
- Test rename scenario

---

## Testing

### Unit tests (per adapter)
- `readKnowledge()` returns `""` when file does not exist
- `writeKnowledge(content)` creates `.teamrc/` directory and writes to correct path
- `readKnowledge()` after `writeKnowledge()` returns same content
- `uninstall()` deletes knowledge file at new path
- Generated agent files reference correct knowledge path in instruction text

### Integration tests
- Two teams on same project get isolated knowledge files
- `teamrc sync` round-trips knowledge through relay to correct per-team file
- Team rename preserves knowledge via file rename
- Heroku-style names are unique across 1000 generations (statistical test)

### Existing test files to update
- `cli/src/__tests__/daemon.test.ts`
- `cli/src/__tests__/openclaw-rules.test.ts`
- `cli/src/__tests__/gemini-rules.test.ts`
- `cli/src/__tests__/validation.test.ts`

---

## Decisions

| Decision | Rationale |
|----------|-----------|
| `.teamrc/` not project root | Already exists, already gitignored, keeps teamrc artifacts together |
| Team slug in filename, not subdirectory | One file per team doesn't justify a directory. `knowledge-<slug>.md` is simpler than `<slug>/knowledge.md` |
| OpenClaw stays in `~/.openclaw/` | All OpenClaw state lives there; moving just knowledge to `~/.teamrc/` scatters state |
| No shared cross-team knowledge | Matches explicit-assignment principle. Revisit on user demand |
| Heroku-style names on create | Unique slugs by default, no collision handling needed, memorable |
| Orchestrator = read-only, subagents = read+write | Subagents do the work and discover the knowledge. Orchestrator writing creates duplicates |
| Append-only instruction to LLMs | Deletion/compaction is a system concern (daemon/CLI), not an agent concern |
| No knowledge compaction yet | 512KB cap is sufficient. Future: `teamrc knowledge compact` CLI command |
| `"team"` as fallback slug | Safe default for commands without team context (doctor, import) |
| Glob-delete on `teamrc delete` | `uninstall()` deletes `knowledge-*.md` so it works without knowing the slug |

---

## Out of Scope

- Cross-team knowledge sharing
- Knowledge compaction / summarization
- Section-based merge (current line-based dedup is sufficient)
- Platform-specific instruction text variations (one template is enough)
- Knowledge file migration from legacy paths (orphaned files are harmless)
