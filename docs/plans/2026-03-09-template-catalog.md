# Template Catalog: Agents, Skills, and Teams

**Date**: 2026-03-09
**Status**: Final

## Platform Research Summary

### Agent file formats across platforms

| Platform | Agent file | Frontmatter fields | Body = |
|----------|-----------|-------------------|--------|
| **Claude Code** | `.claude/agents/*.md` | `name`, `description`, `model`, `tools`, `disallowedTools`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `isolation`, `permissionMode`, `maxTurns` | System prompt |
| **Cursor** | `.cursor/agents/*.md` | `name`, `description`, `model`, `readonly`, `background` | System prompt |
| **Codex** | `.codex/agents/*.toml` | `description`, `config_file`, `model`, `model_reasoning_effort`, `sandbox_mode`, `developer_instructions` | N/A (TOML) |
| **Gemini** | `.gemini/agents/*.md` | `name`, `description`, `kind`, `display_name`, `tools`, `model`, `temperature`, `max_turns`, `timeout_mins` | System prompt |
| **OpenHands** | `.agents/agents/*.md` | `name`, `description`, `model`, `tools`, `skills`, `max_iteration_per_run`, `color`, `hooks` | System prompt |

### Per-agent skills: which platforms support it natively?

| Platform | Native `skills` field? | Behavior |
|----------|----------------------|----------|
| **Claude Code** | **YES** | Listed skills are injected into subagent context at startup. Subagents do NOT inherit parent skills. |
| **OpenHands** | **YES** | Listed skills are resolved and injected into subagent context. |
| **Cursor** | No | Skills are project-level only. |
| **Codex** | No | Skills are project-level via `.agents/skills/`. |
| **Gemini** | No | Skills are project-level only. |

### Per-agent rules: which platforms support it?

**None.** No platform has per-agent rules. Rules are always project-level:
- Claude Code: `.claude/rules/*.md` (auto-loaded for all sessions, including subagents)
- Cursor: `.cursor/rules/*.mdc` (project-level, four application modes)
- Codex: no rules concept (uses `AGENTS.md` and `developer_instructions`)
- Gemini: "policies" are tool permissions, not behavioral rules
- OpenHands: no rules concept

### Skills vs rules

| Aspect | Rules | Skills (SKILL.md) |
|--------|-------|-------------------|
| Loading | Always in context (full content) | Progressive disclosure: name+description at startup (~50-100 tokens), full body on activation |
| Token cost | High (always loaded) | Low at startup, scales with use |
| User-invocable | No | Yes (`/skill-name`) |
| Can include scripts/assets | No | Yes (`scripts/`, `references/`, `assets/`) |
| Can run in subagent | No | Yes (Claude Code `context: fork`) |
| Standard | Platform-specific | Agent Skills open standard (32+ platforms) |
| Per-agent assignment | No | Yes (Claude Code, OpenHands) |

### SOUL.md — does it exist?

**No.** No platform uses a "SOUL.md" file. The agent's personality/identity is always the markdown body of the agent file (after frontmatter). The teamrc OpenClaw adapter invented `SOUL.md` — it does not match native OpenHands format and must be rewritten.

### OpenClaw adapter: current state vs reality

| What teamrc does | What OpenHands actually uses |
|-----------------|----------------------------|
| `~/.openclaw/workspaces/trc-{agent}/SOUL.md` | `.agents/agents/trc-{agent}.md` (body = soul) |
| `~/.openclaw/workspaces/trc-{agent}/AGENTS.md` | Agent body + project AGENTS.md |
| `~/.openclaw/openclaw.json` | No such file (config at `~/.openhands/`) |
| `~/.openclaw/workspace/skills/` | `.agents/skills/` or `~/.agents/skills/` |

### agency-agents comparison (msitarzewski/agency-agents)

- **61 agents** across **9 divisions** (Engineering, Design, Marketing, Product, Project Management, Testing, Support, Spatial Computing, Specialized)
- **No team templates** — divisions are just directories. Teams composed ad-hoc via prompt templates and NEXUS orchestration strategy.
- **No skills or rules** — everything baked into 200-600 line self-contained agent markdown files.
- Each agent has: YAML frontmatter (`name`, `description`, `color`), then sections: Identity & Memory, Core Mission, Critical Rules, Technical Deliverables, Workflow Process, Communication Style, Success Metrics.

---

## Design Decisions

### 1. Unify Rule + Skill into Skill

Rules are skills with `alwaysApply: true`. One interface, one catalog. When writing to platforms:
- `alwaysApply: true` or has `globs` → write as native rule file
- Otherwise → write as native SKILL.md file

### 2. Per-agent skills are real — use them

Claude Code and OpenHands natively support `skills` in agent frontmatter. teamrc should use this when writing to those platforms. For Cursor/Gemini/Codex, inline skill content into the agent body.

### 3. Agent souls contain identity only

The soul is the agent's system prompt: who they are, how they work, their principles. Skills (process knowledge, constraints) are separate and composable. This is what makes teamrc valuable over static agent files like agency-agents — you can swap skills across agents without duplicating text.

### 4. No SOUL.md — soul goes in the agent file body

Every platform stores the soul as the markdown body of the agent file. teamrc does the same.

### 5. Per-agent skill assignment lives in the team template

Agents in the catalog don't declare their skills. Teams compose agents + assign skills. This keeps agents reusable across different team contexts.

---

## Directory Structure

```
templates/
├── agents/                    # ~60 reusable agent definitions
│   ├── _index.yaml            # Categories + display order
│   ├── product-manager.yaml
│   ├── frontend-dev.yaml
│   └── ...
├── skills/                    # ~30 skills (includes what were "rules")
│   ├── _index.yaml            # Categories + display order
│   ├── write-tests.yaml       # alwaysApply: true → written as native rule
│   ├── tdd.yaml               # on-demand skill → written as SKILL.md
│   └── ...
└── teams/                     # ~12 team compositions
    ├── _index.yaml            # Display order
    ├── fullstack.yaml
    ├── backend.yaml
    └── ...
```

---

## File Formats

### Agent (`templates/agents/frontend-dev.yaml`)

```yaml
name: frontend-dev
role: Frontend developer
category: core-dev
soul: |
  You are the frontend developer. You build the user-facing interface —
  components, pages, state management, and API integration.

  ## Workflow
  1. Review the UX spec and identify components, pages, and data requirements
  2. Plan the component hierarchy and state management approach before writing code
  3. Build components bottom-up: primitives first, then compositions
  4. Integrate with backend APIs, handling loading, error, and empty states
  5. Write tests for interactive behavior and edge cases
  6. Ensure accessibility: semantic HTML, ARIA attributes, keyboard handlers

  ## Principles
  - Components should be self-contained and reusable by default
  - Type everything — no `any`, no untyped props
  - Handle every state: loading, error, empty, partial, success
  - Performance matters: lazy-load heavy components, minimize re-renders

  ## Communication
  You communicate in terms of components, props, and user interactions.
  When a UX spec is ambiguous, ask the ux-designer for clarification.
  You coordinate with the backend-dev on API contracts and data shapes.
```

No skills, no rules. Just identity.

### Agent Index (`templates/agents/_index.yaml`)

```yaml
categories:
  - id: core-dev
    label: Core Development
    agents:
      - team-lead
      - frontend-dev
      - backend-dev
      - fullstack-dev
      - mobile-dev
      - api-designer
      - database-engineer
      - systems-programmer

  - id: language
    label: Language Specialists
    agents:
      - rust-dev
      - go-dev
      - python-dev
      - java-dev
      - elixir-dev
      - swift-dev

  - id: infrastructure
    label: Infrastructure
    agents:
      - devops-engineer
      - cloud-architect
      - sre
      - kubernetes-specialist
      - ci-cd-engineer
      - platform-engineer

  - id: quality
    label: Quality & Security
    agents:
      - qa-engineer
      - security-engineer
      - penetration-tester
      - code-reviewer
      - accessibility-specialist
      - performance-engineer

  - id: data-ai
    label: Data & AI
    agents:
      - data-engineer
      - ml-engineer
      - data-analyst
      - ai-researcher
      - prompt-engineer
      - llm-ops

  - id: dx
    label: Developer Experience
    agents:
      - dx-engineer
      - technical-writer
      - api-docs-writer
      - sdk-developer
      - onboarding-specialist

  - id: specialized
    label: Specialized Domains
    agents:
      - game-dev
      - embedded-dev
      - blockchain-dev
      - compiler-engineer
      - graphics-programmer
      - audio-engineer

  - id: business
    label: Business & Product
    agents:
      - product-manager
      - ux-designer
      - ux-researcher
      - growth-engineer
      - analytics-engineer
      - technical-pm

  - id: orchestration
    label: Meta & Orchestration
    agents:
      - architect
      - release-manager
      - incident-commander
      - migration-specialist
      - monorepo-engineer

  - id: research
    label: Research & Analysis
    agents:
      - research-analyst
      - competitive-analyst
      - market-researcher
      - content-strategist
      - seo-specialist
      - copywriter
```

### Skill (`templates/skills/tdd.yaml`) — on-demand skill

```yaml
id: tdd
title: Test-Driven Development
category: process
description: "Systematic TDD workflow for building features test-first"
userInvocable: true
body: |
  When building a new feature or fixing a bug, follow this TDD process:

  1. **Red**: Write a failing test that describes the expected behavior
  2. **Green**: Write the minimum code to make the test pass
  3. **Refactor**: Clean up the code while keeping tests green

  Guidelines:
  - Write the test BEFORE the implementation, not after
  - Each test should test one behavior, not one function
  - Test names should describe the behavior: "creates user with valid email"
  - Don't test implementation details — test the contract
  - Run the full test suite before committing
```

### Skill (`templates/skills/write-tests.yaml`) — always-on (becomes native rule)

```yaml
id: write-tests
title: Write Tests
category: quality
description: "Testing requirements for new functions, endpoints, and components"
alwaysApply: true
body: |
  Every new function, endpoint, or component must have corresponding tests
  before the change is considered complete. Prefer unit tests for pure logic
  and integration tests for I/O boundaries. If modifying existing code,
  update or add tests to cover the changed behavior.
```

### Skill with globs (`templates/skills/no-any-types.yaml`) — file-scoped rule

```yaml
id: no-any-types
title: No Any Types
category: quality
description: "TypeScript strict typing requirements"
alwaysApply: false
globs:
  - "**/*.ts"
  - "**/*.tsx"
body: |
  Never use `any` type. Use `unknown` for truly unknown types and narrow
  with type guards. All function parameters and return types must be
  explicitly typed.
```

### Skill Index (`templates/skills/_index.yaml`)

```yaml
categories:
  - id: process
    label: Development Process
    skills:
      - tdd
      - code-review
      - pair-programming
      - refactoring
      - debugging-systematic

  - id: architecture
    label: Architecture
    skills:
      - api-design-first
      - schema-design
      - event-driven
      - microservices-decomposition

  - id: quality
    label: Quality
    skills:
      - write-tests
      - security-audit
      - performance-profiling
      - accessibility-audit
      - load-testing
      - no-any-types

  - id: documentation
    label: Documentation
    skills:
      - adr-writing
      - api-documentation
      - runbook-writing
      - changelog-maintenance

  - id: workflow
    label: Workflow
    skills:
      - small-commits
      - conventional-commits
      - git-flow
      - trunk-based-dev
      - feature-flags
      - blue-green-deploy

  - id: constraints
    label: Constraints
    skills:
      - brand-voice
      - cite-sources
      - document-findings
      - verify-fixes
      - infra-as-code
      - rollback-plan

  - id: analysis
    label: Analysis
    skills:
      - root-cause-analysis
      - incident-postmortem
      - dependency-audit
      - tech-debt-assessment
```

### Team (`templates/teams/fullstack.yaml`)

```yaml
label: Full-Stack Product
description: "Ship features end-to-end with PM, design, and engineering"
defaultPlatforms:
  - claude-code
  - cursor
  - copilot

name: product-team

agents:
  - product-manager
  - team-lead
  - ux-designer
  - frontend-dev
  - backend-dev
  - qa-engineer

skills:
  - write-tests
  - small-commits

agentSkills:
  team-lead:
    - small-commits
  frontend-dev:
    - write-tests
    - no-any-types
  backend-dev:
    - write-tests
    - small-commits
  qa-engineer:
    - write-tests
```

### Team Index (`templates/teams/_index.yaml`)

```yaml
order:
  - fullstack
  - backend
  - frontend
  - security
  - mobile
  - data-ml
  - marketing
  - research
  - devops
  - documentation
  - startup-mvp
  - custom
```

---

## Team Templates (~12)

| Template | Description | Agents | Key skills |
|----------|------------|--------|-----------|
| **fullstack** | Ship features end-to-end | PM, team-lead, UX designer, frontend, backend, QA | write-tests, small-commits |
| **backend** | APIs, services, data pipelines | architect, backend-dev, code-reviewer, database-engineer | api-design-first, write-tests |
| **frontend** | User interfaces and design systems | UX designer, frontend-dev, accessibility-specialist, qa-engineer | write-tests, no-any-types |
| **security** | Security assessment and hardening | pentest-lead, vuln-analyst, code-auditor, report-writer | document-findings, verify-fixes |
| **mobile** | Mobile app development | mobile-dev, backend-dev, ux-designer, qa-engineer | write-tests, small-commits |
| **data-ml** | Data pipelines and ML systems | data-engineer, ml-engineer, data-analyst | write-tests, schema-design |
| **marketing** | Campaigns, content, growth | marketing-lead, copywriter, seo-specialist, analytics-engineer | brand-voice |
| **research** | Deep research with verification | lead-researcher, analyst, fact-checker, writer | cite-sources |
| **devops** | Infrastructure and reliability | platform-engineer, sre, security-engineer | infra-as-code, rollback-plan |
| **documentation** | Technical writing and API docs | technical-writer, api-docs-writer, onboarding-specialist | adr-writing, api-documentation |
| **startup-mvp** | Small team, ship fast | product-manager, fullstack-dev, qa-engineer | write-tests, small-commits |
| **custom** | Start from scratch | (none) | (none) |

---

## Resolution at `teamrc init` Time

1. User selects a team template (or "custom")
2. Load team YAML → resolve agent refs from `templates/agents/`
3. Resolve skill refs from `templates/skills/`
4. Produce a fully self-contained `.teamrc.yaml`:

```yaml
name: product-team
members:
  - name: product-manager
    role: Product manager
    soul: |
      You are the product manager...
    skills: []          # no per-agent skills assigned for this agent
  - name: frontend-dev
    role: Frontend developer
    soul: |
      You are the frontend developer...
    skills:             # per-agent skills from agentSkills
      - write-tests
      - no-any-types
skills:
  - id: write-tests
    title: Write Tests
    description: "Testing requirements for new code"
    alwaysApply: true
    body: |
      Every new function...
  - id: small-commits
    title: Small Commits
    description: "Keep commits focused and reviewable"
    alwaysApply: true
    body: |
      Keep each commit...
  - id: no-any-types
    title: No Any Types
    description: "TypeScript strict typing requirements"
    globs: ["**/*.ts", "**/*.tsx"]
    body: |
      Never use any type...
```

No template refs remain. Fully portable.

---

## How Adapters Write the Resolved Team

### Project-level skills

Based on `alwaysApply` and `globs`, each skill in `TeamDefinition.skills` routes to:

| Condition | Claude Code | Cursor | Codex | Gemini | OpenHands |
|-----------|------------|--------|-------|--------|-----------|
| `alwaysApply: true` | `.claude/rules/trc-{id}.md` | `.cursor/rules/trc-{id}.mdc` (`alwaysApply: true`) | Section in `AGENTS.md` | Section in `GEMINI.md` | Repo skill in `.agents/skills/` |
| Has `globs` | `.claude/rules/trc-{id}.md` (with `paths`) | `.cursor/rules/trc-{id}.mdc` (with `globs`) | Section in `AGENTS.md` | Section in `GEMINI.md` | Repo skill in `.agents/skills/` |
| Neither (on-demand) | `.claude/skills/trc-{id}/SKILL.md` | `.cursor/skills/trc-{id}/SKILL.md` | `.agents/skills/trc-{id}/SKILL.md` | `.agents/skills/trc-{id}/SKILL.md` | `.agents/skills/trc-{id}/SKILL.md` |

### Per-agent skills

Based on `TeamMember.skills` (string[] referencing skill IDs):

| Platform | How per-agent skills are written |
|----------|--------------------------------|
| **Claude Code** | `skills` field in agent frontmatter (native) |
| **OpenHands** | `skills` field in agent frontmatter (native) |
| **Cursor** | Inlined as `## Skills` section in agent body |
| **Codex** | Inlined in `developer_instructions` in agent TOML |
| **Gemini** | Inlined as `## Skills` section in agent body |

### Agent files

| Platform | Path | Format |
|----------|------|--------|
| Claude Code | `.claude/agents/trc-{name}.md` | YAML frontmatter (`name`, `description`, `model`, `skills`) + body |
| Cursor | `.cursor/agents/trc-{name}.md` | YAML frontmatter (`name`, `description`) + body |
| Codex | `.codex/agents/trc-{name}.toml` | TOML with `developer_instructions` |
| Gemini | `.gemini/agents/trc-{name}.md` | YAML frontmatter (`name`, `description`) + body |
| OpenHands | `.agents/agents/trc-{name}.md` | YAML frontmatter (`name`, `description`, `skills`) + body |

---

## Data Model Changes

### Current interfaces (base.ts)

```typescript
// REMOVE
interface Rule {
  id: string;
  title?: string;
  globs?: string[];
  alwaysApply?: boolean;
  body: string | { source: string };
}

// CURRENT
interface Skill {
  id: string;
  title?: string;
  description?: string;
  body?: string | { source: string };
}

interface TeamMember {
  name: string;
  role: string;
  soul?: string;
  rules?: string[];   // references Rule.id
  skills?: string[];  // references Skill.id
}

interface TeamDefinition {
  name: string;
  members: TeamMember[];
  rules?: Rule[];
  skills?: Skill[];
}
```

### New interfaces (base.ts)

```typescript
interface Skill {
  id: string;
  title?: string;
  description?: string;        // for Cursor intelligent mode + SKILL.md description
  category?: string;           // for catalog browsing
  alwaysApply?: boolean;       // true → write as native rule
  globs?: string[];            // file-scoped → write as native rule with paths/globs
  userInvocable?: boolean;     // true → slash command in Claude Code
  body: string | { source: string };
}

interface TeamMember {
  name: string;
  role: string;
  soul?: string;
  skills?: string[];  // references Skill.id (per-agent assignment)
}

interface TeamDefinition {
  name: string;
  members: TeamMember[];
  skills?: Skill[];            // project-level skills (was rules + skills)
}
```

### resolve-rules.ts → resolve-skills.ts

```typescript
// Remove resolveAgentRules entirely
// Keep resolveAgentSkills (unchanged logic, just no more rules)

export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || agent.skills.length === 0 || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
}
```

---

## Implementation Phases

### Phase 1: Data model migration — DONE

**Goal**: Merge Rule into Skill, remove Rule from the entire codebase (CLI + web + relay).

#### CLI (TypeScript)

1. Update `Skill` interface in `base.ts`: add `alwaysApply`, `globs`, `description`, `userInvocable`
2. Remove `Rule` interface from `base.ts`
3. Remove `rules?: Rule[]` from `TeamDefinition`, remove `rules?: string[]` from `TeamMember`
4. Rename `resolve-rules.ts` → `resolve-skills.ts`, remove `resolveAgentRules`
5. Update all adapters to use unified Skill:
   - **claude-code.ts**: Route skills to `.claude/rules/` or `.claude/skills/` based on `alwaysApply`/`globs`. Use native `skills` frontmatter for per-agent skills.
   - **cursor.ts**: Route skills to `.cursor/rules/` or `.cursor/skills/` based on `alwaysApply`/`globs`. Inline per-agent skills into body.
   - **codex.ts**: No native rule support. Inline `alwaysApply` skills into `AGENTS.md`. Write on-demand skills to `.agents/skills/`. Inline per-agent skills into `developer_instructions`.
   - **gemini.ts**: Inline `alwaysApply` skills into `GEMINI.md`. Write on-demand skills to `.agents/skills/` or `.gemini/skills/`. Inline per-agent skills into body.
   - **openclaw.ts**: Complete rewrite (see Phase 2).
6. Update `team-yaml.ts`: remove `validateRuleId`, update read/write for unified skills format (no `rules` key)
7. Update `client.ts`: remove `Rule` import, update `remoteTeamToDefinition` to handle skills-only format
8. Update `index.ts` and `templates.ts` to use new interfaces
9. Update tests: `resolve-rules.test.ts` → `resolve-skills.test.ts`, `integration-rules.test.ts`, `types.test.ts`

#### Web (Elixir/Phoenix)

10. Update `teamrc/lib/teamrc/schema/team.ex`:
    - Remove `field :rules, {:array, :map}, default: []`
    - Keep `field :skills` — skills now include what were rules (with `alwaysApply`, `globs`, `description` fields)
    - Update `changeset/2`: remove `validate_entry_ids(:rules)`, update cast params
11. Update `teamrc/lib/teamrc/schema/member.ex`:
    - Remove `field :rules, {:array, :string}, default: []`
    - Keep `field :skills` for per-agent skill references
    - Update `changeset/2`: remove `rules` from cast
12. Update `teamrc/lib/teamrc/teams.ex`:
    - Remove all `rules` handling from `normalize_team_data/1` and `to_api_map/1`
    - Update `Team.changeset` calls: no more `rules` param
    - Update `Member.changeset` calls: no more `rules` param
13. Update `teamrc/lib/teamrc_web/live/team_live.ex`:
    - Remove `@templates` module attribute (will be replaced by catalog in Phase 3)
    - Remove all `rules`-related assigns: `rules`, per-member `rules` assignment
    - Remove `handle_event("toggle_member_rule", ...)` handler
    - Remove `handle_event("update_rule", ...)`, `handle_event("add_rule", ...)`, `handle_event("remove_rule", ...)` handlers
    - Remove `has_defined_rules?/1` helper
    - Remove rules UI section from `render/1` (the "Rules" tab in advanced panel)
    - Remove per-member rule toggle chips from member cards
    - Update `handle_event("create_team", ...)`: build team with `skills` only, no `rules`
    - Update `handle_event("select_template", ...)`: load `skills` instead of `rules` from template
    - Rename "Rules" references in UI to "Skills" where `alwaysApply` skills replace them
    - Update `item_count/2` calls: remove rule counting
14. Update `teamrc/lib/teamrc_web/controllers/api_controller.ex` if it references rules in API responses
15. Run `mix test` — fix any broken Elixir tests

### Phase 2: Rewrite OpenClaw adapter — DONE

**Goal**: Align with native OpenHands file format.

1. Replace workspace-based architecture with standard agent files:
   - Write to `.agents/agents/trc-{name}.md` (project) or `~/.agents/agents/trc-{name}.md` (global)
   - Standard YAML frontmatter: `name`, `description`, `skills`
   - Soul as markdown body
2. Write skills to `.agents/skills/trc-{id}/SKILL.md` (cross-platform path)
3. Write routing to `AGENTS.md` at project root
4. Remove all `~/.openclaw/` directory usage, `openclaw.json`, `SOUL.md`
5. Update `readTeam()` to parse the new format
6. Update `getHashes()`, `watchPaths()`, `writeFile()`, `readFile()`
7. Update `uninstall()` to clean the new paths

### Phase 3: Catalog structure + YAML loader — DONE

**Goal**: Single source of truth for templates, shared between CLI and web.

#### Catalog files
1. Create `templates/{agents,skills,teams}/` directory structure with `_index.yaml` files
2. Migrate existing template content (from `templates.ts` and flat `templates/*.yaml`) into split YAML files
3. Delete `templates/{fullstack,backend,security,...}.yaml` (old flat files)
4. Delete `templates/_index.yaml` (old index)

#### TypeScript catalog loader
5. Create `cli/src/catalog.ts`:
   - `loadAgent(name: string)` → reads `templates/agents/{name}.yaml`
   - `loadSkill(id: string)` → reads `templates/skills/{id}.yaml`
   - `loadTeam(id: string)` → reads `templates/teams/{id}.yaml`, resolves agent + skill refs
   - `listTeams()` → reads `templates/teams/_index.yaml`, returns ordered list
   - `listAgentCategories()` → reads `templates/agents/_index.yaml`
   - `listSkillCategories()` → reads `templates/skills/_index.yaml`
   - `resolveTeam(teamId: string)` → returns fully resolved TeamDefinition (no refs)
6. Delete `cli/src/templates.ts` (816 lines, replaced by catalog loader)
7. Update `cli/src/index.ts`: replace `TEMPLATES`/`TEMPLATE_ORDER` imports with catalog loader calls
8. Update `selectTemplate()`, `templateToTeamDefinition()` in `index.ts`

#### Elixir catalog loader
9. Create `teamrc/lib/teamrc/catalog.ex`:
   - `list_teams/0` → reads `templates/teams/_index.yaml`, returns ordered list with metadata
   - `load_team/1` → reads team YAML, resolves agent + skill refs from `templates/` dirs
   - `list_agent_categories/0` → reads `templates/agents/_index.yaml`
   - `list_skill_categories/0` → reads `templates/skills/_index.yaml`
   - `resolve_team/1` → returns fully resolved team map (no refs)
   - Uses `YamlElixir` to parse YAML files
   - Templates path: `Application.app_dir(:teamrc, "priv/templates")` (copy at build) or read from repo root

#### Web wizard update
10. Update `teamrc/lib/teamrc_web/live/team_live.ex`:
    - Remove `@templates` module attribute (~700 lines of inline template data)
    - Remove `@template_defaults` module attribute
    - Replace with calls to `Teamrc.Catalog.list_teams()` in `mount/3`
    - Update `handle_event("select_template", ...)` to use `Teamrc.Catalog.resolve_team(key)`
    - Template cards in `render/1` now iterate over catalog data instead of `@templates`
    - Agent preview shows soul excerpts from catalog
11. Update `mix.exs` or build step to copy `templates/` into `priv/templates/` for the Elixir app

### Phase 4: Write catalog content — DONE

**Goal**: ~60 agents, ~30 skills, ~12 teams. (Actual: ~68 agents, ~49 skills, 12 teams.)

Batch by category. Each agent needs:
- `name`, `role`, `category`
- Rich `soul` (15-30 lines: identity, workflow, principles, communication style)

Each skill needs:
- `id`, `title`, `category`, `description`
- `alwaysApply`/`globs`/`userInvocable` as appropriate
- `body` with actionable process instructions

Each team needs:
- `label`, `description`, `defaultPlatforms`, `name`
- `agents` list (refs to catalog)
- `skills` list (project-level refs to catalog)
- `agentSkills` map (per-agent skill assignments)

### Phase 5: CLI wizard enhancement — DONE

**Goal**: Rich template selection and team composition in `teamrc init`.

1. Browse teams by template (current flow, enhanced with more options)
2. Browse agents by category for custom team composition
3. Preview agent souls before selecting
4. Select project-level skills
5. Assign per-agent skills (optional, advanced)

### Phase 6: Web wizard enhancement — DONE

**Goal**: Visual team composition in the web UI.

1. Agent browser with category filters
2. Agent preview cards with soul excerpts
3. Skill picker with description and type indicators
4. Per-agent skill assignment UI
5. Both wizard and CLI produce identical `.teamrc.yaml`

### Phase 7: Adapter improvements (from research) — DONE

**Goal**: Use native platform features we discovered.

1. **Claude Code**: Add `skills` to agent frontmatter (per-agent skills, native)
2. **Cursor**: Add `model`, `readonly`, `background` to agent frontmatter. Add `description` to rule frontmatter (for intelligent mode). Add `disable-model-invocation` to skill frontmatter.
3. **Codex**: Write skills to `.agents/skills/` (correct native path, not `skills/`). Use `multi_agent` feature flag.
4. **Gemini**: Add `tools`, `model`, `temperature`, `max_turns` to agent frontmatter. Write skills to `.agents/skills/` for cross-platform compatibility.
5. **OpenHands**: Use `.agents/` paths (cross-platform), add `skills` to frontmatter.

---

## Agent Catalog (~60)

### Core Development (8)
team-lead, frontend-dev, backend-dev, fullstack-dev, mobile-dev, api-designer, database-engineer, systems-programmer

### Language Specialists (6)
rust-dev, go-dev, python-dev, java-dev, elixir-dev, swift-dev

### Infrastructure (6)
devops-engineer, cloud-architect, sre, kubernetes-specialist, ci-cd-engineer, platform-engineer

### Quality & Security (6)
qa-engineer, security-engineer, penetration-tester, code-reviewer, accessibility-specialist, performance-engineer

### Data & AI (6)
data-engineer, ml-engineer, data-analyst, ai-researcher, prompt-engineer, llm-ops

### Developer Experience (5)
dx-engineer, technical-writer, api-docs-writer, sdk-developer, onboarding-specialist

### Specialized Domains (6)
game-dev, embedded-dev, blockchain-dev, compiler-engineer, graphics-programmer, audio-engineer

### Business & Product (6)
product-manager, ux-designer, ux-researcher, growth-engineer, analytics-engineer, technical-pm

### Meta & Orchestration (5)
architect, release-manager, incident-commander, migration-specialist, monorepo-engineer

### Research & Analysis (6)
research-analyst, competitive-analyst, market-researcher, content-strategist, seo-specialist, copywriter

## Skill Catalog (~30)

### Development Process
tdd, code-review, pair-programming, refactoring, debugging-systematic

### Architecture
api-design-first, schema-design, event-driven, microservices-decomposition

### Quality (mostly alwaysApply: true)
write-tests, security-audit, performance-profiling, accessibility-audit, load-testing, no-any-types

### Documentation (userInvocable: true)
adr-writing, api-documentation, runbook-writing, changelog-maintenance

### Workflow (mostly alwaysApply: true)
small-commits, conventional-commits, git-flow, trunk-based-dev, feature-flags, blue-green-deploy

### Constraints (alwaysApply: true)
brand-voice, cite-sources, document-findings, verify-fixes, infra-as-code, rollback-plan

### Analysis (userInvocable: true)
root-cause-analysis, incident-postmortem, dependency-audit, tech-debt-assessment
