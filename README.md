# teamrc

One team definition. Every AI platform. Every machine.

**[teamrc.ai](https://teamrc.ai)** &middot; [Docs](https://github.com/teamrc-ai/teamrc/wiki)

Define your AI agent team once in `.teamrc.yaml`. teamrc generates native files for Claude Code, Cursor, Codex, Gemini, and OpenClaw — and syncs them across machines, VMs, and projects.

## Quick Start

```bash
# Create a team from a template
npx @teamrc/cli init

# Or join an existing team
npx @teamrc/cli join <invite-code>

# Edit .teamrc.yaml, then sync
npx @teamrc/cli sync
```

No server required for local use:

```bash
npx @teamrc/cli init --local
```

## How It Works

```
.teamrc.yaml     (source of truth, version-controlled)
       |
  CLI commands   (init, apply, sync, push)
       |
platform adapters (Claude Code, Cursor, Codex, OpenClaw, Gemini)
       |
native agent files (.claude/agents/, .cursor/rules/, etc.)
       |
  relay server   (optional, cross-machine sync via teamrc.ai)
```

## Self-Hosting

```bash
docker compose up   # starts Postgres + relay at http://localhost:4000
```

Point the CLI at your relay with `TEAMRC_RELAY=http://localhost:4000` or set `relay:` in `.teamrc.yaml`.

See [docs/deploy-coolify.md](docs/deploy-coolify.md) for production deployment.

## Documentation

- **[Get Started](https://github.com/teamrc-ai/teamrc/wiki/Get-Started)** — Create a synced team in 2 minutes
- **[CLI Reference](https://github.com/teamrc-ai/teamrc/wiki/CLI-Reference)** — All commands with flags and examples
- **[Configuration](https://github.com/teamrc-ai/teamrc/wiki/Configuration)** — `.teamrc.yaml` format and options
- **[Platforms](https://github.com/teamrc-ai/teamrc/wiki/Platforms)** — How teamrc works on each AI platform
- **[Template Catalog](https://github.com/teamrc-ai/teamrc/wiki/Template-Catalog)** — 12 team templates, 68 agents, 49 skills
- **[Sharing & Access](https://github.com/teamrc-ai/teamrc/wiki/Sharing-&-Access)** — Public sharing, access roles, clone/fork
- **[Architecture](https://github.com/teamrc-ai/teamrc/wiki/Architecture)** — System design, auth, sync protocol
- **[API Reference](https://github.com/teamrc-ai/teamrc/wiki/API-Reference)** — REST and WebSocket API
