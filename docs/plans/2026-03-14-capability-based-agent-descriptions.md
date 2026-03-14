# Capability-Based Agent Descriptions

## Problem

Agent descriptions are the primary signal used by AI coding assistants to decide which subagent to dispatch a task to. Our current descriptions are **role-based**, which loses out to built-in agents that have **capability-based** descriptions.

### Current format (all adapters)

```
"Frontend developer on the Acme team. Use when tasks relate to frontend developer."
```

### What built-in agents look like

```
"Deeply analyzes existing codebase features by tracing execution paths, mapping architecture layers, understanding patterns and abstractions, and documenting dependencies to inform new development"
```

When a user asks "research how skills are routed across adapters," the built-in `code-explorer` wins every time — its description is an exact capability match. The teamrc `backend-dev` agent might be equally capable (it has the same tools), but its description doesn't signal that.

### Real-world impact

In a test session, a user loaded a teamrc research team and asked for codebase analysis. The orchestrating agent chose `feature-dev:code-explorer` over the user's `trc-*` agents because the descriptions matched the task better. The user had to ask "which agents are you using?" to discover the mismatch.

## Current Implementation

Agent descriptions are generated from `member.role` in each adapter:

| Adapter | Template | File:Line |
|---|---|---|
| Claude Code | `"{role} on the {team} team. Use when tasks relate to {role}."` | `claude-code.ts:442` |
| Cursor | `"{role} on the {team} team. Use when tasks relate to {role}."` | `cursor.ts:261` |
| Codex | `"{role}"` | `codex.ts:260` |
| Gemini | `"{role}"` | `gemini.ts:388` |
| OpenClaw | `"{role}"` | `openclaw.ts:362` |

The `member.role` field is a short label like "Frontend developer" or "QA engineer." There is no structured capability data anywhere in the `TeamMember` interface.

## Proposal

### Option A: Auto-generate from soul + skills (no schema change)

Use the agent's existing `soul` (instructions) and assigned `skills` to generate a richer description at write time. No changes to `.teamrc.yaml` schema.

```typescript
function buildDescription(member: TeamMember, team: TeamDefinition): string {
  const skills = resolveAgentSkills(member, team);
  const skillNames = skills.map(s => s.title || s.id).join(", ");

  // Start with role
  let desc = `${member.role} on the ${team.name} team.`;

  // Add skill capabilities if any
  if (skillNames) {
    desc += ` Skilled in ${skillNames}.`;
  }

  // Add soul-derived capabilities (first sentence or key phrases)
  if (member.soul) {
    const firstSentence = member.soul.split(/[.\n]/)[0].trim();
    if (firstSentence.length < 100) {
      desc += ` ${firstSentence}.`;
    }
  }

  desc += ` Use when tasks relate to ${member.role.toLowerCase()}.`;
  return desc;
}
```

**Pros**: Zero schema change, works with existing teams immediately.
**Cons**: Auto-generated text may be awkward. Soul text wasn't written for this purpose.

### Option B: Add `description` field to `TeamMember` (schema change)

Add an optional `description` field to the `TeamMember` interface that users/templates can set explicitly. Fall back to auto-generation if not set.

```yaml
# .teamrc.yaml
members:
  - name: backend-dev
    role: Backend developer
    description: "Analyzes TypeScript and Elixir codebases, designs API architecture, traces execution paths, and reviews adapter patterns"
    skills:
      - write-tests
      - structured-error-handling
```

```typescript
interface TeamMember {
  name: string;
  role: string;
  description?: string;  // NEW — capability-oriented dispatch hint
  soul?: string;
  skills?: string[];
}
```

The adapter would use `member.description` if present, otherwise fall back to the current role-based template.

**Pros**: Full user control. Descriptions can be tuned for dispatch accuracy.
**Cons**: Schema change. Existing teams don't benefit without updates. Another field to maintain.

### Option C: Template catalog provides capabilities (catalog change)

Add a `capabilities` list to agent templates in `templates/agents/*.yaml`. When a team is created from a template, capabilities flow into the description.

```yaml
# templates/agents/backend-dev.yaml
name: backend-dev
role: Backend developer
capabilities:
  - API architecture and design
  - database schema and query optimization
  - codebase analysis and code review
  - debugging and performance profiling
```

**Pros**: Good defaults from catalog. Users don't need to write descriptions.
**Cons**: Only works for catalog-sourced agents. Custom agents still need manual descriptions.

### Recommendation: Option B with catalog defaults (A+B+C combined)

1. Add `description` to `TeamMember` interface
2. Update catalog templates with good default descriptions
3. Auto-generate from role + skills as fallback when no explicit description exists
4. Update all 5 adapters to use the new description

This gives the best of all approaches: catalog agents get great descriptions out of the box, custom agents get auto-generated ones, and power users can override with explicit text.

## Scope

### Files to modify

1. `cli/src/adapters/base.ts` — Add `description` to `TeamMember`, add `buildAgentDescription()` helper
2. `cli/src/adapters/claude-code.ts` — Use new description in `buildAgentFile()`
3. `cli/src/adapters/cursor.ts` — Use new description in `writeAgentMd()`
4. `cli/src/adapters/codex.ts` — Use new description in `writeAgentToml()`
5. `cli/src/adapters/gemini.ts` — Use new description in `buildAgentFile()`
6. `cli/src/adapters/openclaw.ts` — Use new description in `buildAgentFile()`
7. `cli/src/team-yaml.ts` — Parse/serialize `description` field
8. `templates/agents/*.yaml` — Add `description` to ~68 agent templates
9. `teamrc/lib/teamrc_web/controllers/team_controller.ex` — Pass description through API
10. `teamrc/lib/teamrc_web/live/team_detail_live.ex` — Edit description in web UI

### Migration

No migration needed — `description` is optional. Existing teams get the auto-generated fallback. New teams from catalog get template descriptions.
