# Rename: teamrc → teamrc

**Status:** Plan

## Scope

~709 string occurrences across ~100 source files, plus directory/file renames.

### String mapping

| Old | New | Context |
|---|---|---|
| `teamrc` | `teamrc` | Brand name in prose, UI, docs |
| `Teamrc` | `Teamrc` | Elixir module prefix |
| `teamrc` | `teamrc` | Package names, paths, config keys, CLI commands |
| `TEAMRC` | `TEAMRC` | Env vars (`TEAMRC_RELAY`) |
| `TeamrcWeb` | `TeamrcWeb` | Phoenix web module prefix |
| `teamrc_web` | `teamrc_web` | Phoenix web directory/file names |
| `trc_ak_` | `trc_ak_` | Token prefix |
| `trc_inv_` | `trc_inv_` | Invite prefix |
| `tb-` | `trc-` | Agent file prefix, rule/skill prefix in adapters |
| `~/.teamrc/` | `~/.teamrc/` | Config directory |
| `teamrc.dev` | `teamrc.dev` | Domain (in docs/URLs) |

## Tasks

### Task 1: Rename Elixir directories and files

Rename the directory structure first (before editing contents).

```
teamrc/                          → teamrc/
teamrc/lib/teamrc/          → teamrc/lib/teamrc/
teamrc/lib/teamrc.ex        → teamrc/lib/teamrc.ex
teamrc/lib/teamrc_web/      → teamrc/lib/teamrc_web/
teamrc/lib/teamrc_web.ex    → teamrc/lib/teamrc_web.ex
teamrc/test/teamrc/         → teamrc/test/teamrc/
teamrc/test/teamrc_web/     → teamrc/test/teamrc_web/
```

Use `git mv` for all renames to preserve history.

### Task 2: Rename Elixir module names and config keys

Find and replace in all `.ex` and `.exs` files:

- `Teamrc` → `Teamrc` (module prefix — covers `Teamrc.Teams`, `Teamrc.Schema.*`, etc.)
- `TeamrcWeb` → `TeamrcWeb`
- `teamrc_web` → `teamrc_web` (in strings, atoms)
- `:teamrc` → `:teamrc` (OTP app name, config keys)
- `teamrc.dev` → `teamrc.dev` (URLs)
- `"teamrc"` → `"teamrc"` (string references)

Files: ~55 Elixir source + ~25 test files.

Update `mix.exs`: app name, module, project name.

### Task 3: Rename CLI references

Find and replace in all `.ts` files:

- `teamrc` → `teamrc` (in strings, comments, paths)
- `teamrc` → `teamrc` (brand references in console output)
- `TeamrcClient` → `TeamrcClient` (class name)
- `TeamrcConfig` → `TeamrcConfig` (interface name)
- `.teamrc/` → `.teamrc/` (config dir path)
- `TEAMRC_RELAY` → `TEAMRC_RELAY` (env var)

Update `cli/package.json`: name, bin, description.
Update `cli/package-lock.json`: regenerate after package.json change.

### Task 4: Rename docs and markdown

Find and replace in all `.md` files:

- `teamrc` → `teamrc`
- `teamrc` → `teamrc`
- `TEAMRC` → `TEAMRC`
- `.teamrc/` → `.teamrc/`

Files: CLAUDE.md, README.md, docs/plans/*.md, .claude/agents/*.md, .claude/team-knowledge.md

### Task 5: Rename web assets and templates

- `teamrc/assets/css/app.css` — brand references
- `teamrc/assets/js/app.js` — any references
- `.heex` templates — title, brand name, URLs
- Root layout `root.html.heex` — page title, meta tags

### Task 6: Rename config files

- `teamrc/config/config.exs` — app name, endpoint config
- `teamrc/config/dev.exs` — database name, endpoint
- `teamrc/config/prod.exs` — host, URL
- `teamrc/config/runtime.exs` — env vars, database URL
- `teamrc/config/test.exs` — database name, config keys

Database names: `teamrc_dev` → `teamrc_dev`, `teamrc_test` → `teamrc_test`

### Task 7: Rename subagent files

- `.claude/agents/tb-*.md` — keep `tb-` prefix or rename to `trc-`?
- Update CLAUDE.md team section

### Task 8: Rebuild CLI dist

```
cd teamrc && mix deps.get
cd cli && npm run build
```

### Task 9: Create and migrate new databases

```
cd teamrc && mix ecto.create && mix ecto.migrate
```

### Task 10: Verify

- `cd teamrc && mix test` — all 114 tests pass
- `cd cli && npm test` — all 67 tests pass
- `grep -ri "teamrc"` — zero hits (except maybe old plan docs, which are historical)

## Order of execution

1. Task 1 (dir renames) — must be first
2. Tasks 2-6 in parallel (string replacements)
3. Task 7 (subagent files)
4. Task 8 (rebuild)
5. Task 9 (databases)
6. Task 10 (verify)

## Risk

- **Database**: Existing dev/test databases are named `teamrc_*`. Need to recreate or rename.
- **Config dir**: `~/.teamrc/` has existing keypairs. Users would need to move to `~/.teamrc/` or we add a migration path.
- **Git history**: Using `git mv` preserves rename tracking. Single commit preferred.
