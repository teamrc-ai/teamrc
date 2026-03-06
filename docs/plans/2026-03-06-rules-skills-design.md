# Design: Extend Team YAML with Rules & Skills

## Problem

teamrc syncs agent teams across platforms, but currently only handles agent definitions (name, role, soul). Modern AI coding platforms support **rules** (coding conventions, guidelines) and **skills** (reusable capabilities). We need to extend the YAML schema to support these concepts and map them to 10 target platforms.

## Target Platforms

1. Claude Code - `.claude/agents/*.md`, `CLAUDE.md`
2. OpenClaw - `SOUL.md`, `AGENTS.md` in workspaces
3. Cursor - `.cursor/rules/*.mdc` with YAML frontmatter
4. Codex (OpenAI) - `AGENTS.md` (hierarchical), Skills
5. Gemini CLI - `GEMINI.md`, custom commands
6. Claude Desktop - `claude_desktop_config.json`, MCP servers
7. Windsurf - `.windsurf/rules/*.md` with globs
8. Aider - `CONVENTIONS.md`, `.aider.conf.yml`
9. Continue.dev - `.continue/config.yaml`, rules with globs
10. GitHub Copilot - `.github/copilot-instructions.md`, `.github/agents/*.agent.md`

## Schema Design

```yaml
team:
  name: my-team
  version: 1

rules:
  - id: rule_code_style
    title: Code Style
    globs: ["*.ts", "*.js"]     # Optional: file-scoped activation
    alwaysApply: true            # Optional: always vs conditional
    body: |
      Use eslint + prettier defaults.

  - id: rule_security
    title: Security Guidelines
    body:
      source: ./rules/security.md   # External file reference

skills:
  - id: skill_repo_search
    title: Repository Search
    description: Search the repository for files and code patterns
    body: |
      Use grep for content, glob for files.

agents:
  - id: agent_architect
    name: architect
    role: design system architecture
    instructions:
      base: |
        You are part of Team my-team.
    rules:
      - rule_code_style
      - rule_security
    skills:
      - skill_repo_search
```

## Cross-Platform Mapping

| YAML Concept | Claude Code | Cursor | Codex | Copilot | Windsurf | Gemini | Aider | Continue | OpenClaw | Claude Desktop |
|-------------|------------|--------|-------|---------|----------|--------|-------|----------|---------|---------------|
| `rules[].body` | Agent `.md` section | `.mdc` file | `AGENTS.md` | `.instructions.md` | `.windsurf/rules/*.md` | `GEMINI.md` | `CONVENTIONS.md` | Rules config | `AGENTS.md` | N/A |
| `rules[].globs` | N/A | `globs:` frontmatter | N/A | `applyTo:` | Glob patterns | N/A | N/A | `globs:` | N/A | N/A |
| `skills[].body` | Agent skill file | `SKILL.md` | Skills | `.agent.md` | N/A | Custom cmd | N/A | Prompts | Workspace | MCP |
| `agents[].instructions` | Agent body | N/A | `AGENTS.md` | N/A | N/A | N/A | N/A | N/A | `SOUL.md` | N/A |

## TypeScript Types

```ts
interface TeamConfig {
  team: { name: string; version?: number }
  rules?: Rule[]
  skills?: Skill[]
  agents: Agent[]
}

interface Rule {
  id: string
  title?: string
  globs?: string[]
  alwaysApply?: boolean
  body: string | { source: string }
}

interface Skill {
  id: string
  title?: string
  description?: string
  body?: string | { source: string }
}

interface Agent {
  id: string
  name: string
  role?: string
  instructions?: { base?: string }
  rules?: string[]   // references Rule.id
  skills?: string[]  // references Skill.id
}
```

## Implementation Approach

1. **Extend types** - Add Rule, Skill interfaces to `adapters/base.ts`
2. **Update YAML loader** - Parse rules/skills in `team-yaml.ts`, backward-compatible
3. **Add resolvers** - `resolveRules.ts`, `resolveSkills.ts` for agent references
4. **Extend source resolver** - Support `{ source: "./path" }` for rule/skill bodies
5. **Update adapters** - Inject resolved rules/skills into platform-native formats
6. **Tests** - Extend `team-yaml.test.ts` and `resolve-source.test.ts`

## Backward Compatibility

- `rules` and `skills` are optional in the schema
- Existing YAML with only `name` + `members` continues to work
- Old TeamDefinition interface preserved; new fields added alongside
