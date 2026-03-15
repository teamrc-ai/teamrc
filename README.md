# Teamrc

**Define your AI team once. Sync it everywhere.**

[teamrc.ai](https://teamrc.ai) &middot; [Docs](https://github.com/teamrc-ai/teamrc/wiki)

---

Teamrc keeps your agents, skills, and shared knowledge consistent across Claude Code, Cursor, Codex, Gemini, and OpenClaw. Define everything once in `.teamrc.yaml` and sync it where your team works. Change something on one machine, every other machine picks it up.

- **Consistent agents** across every AI tool you use
- **Shared skills and knowledge** across teammates and machines
- **One command to onboard** a new machine or VM
- **No manual duplication** of prompt files across platforms

Works locally with no server required. Connect to a relay (hosted at [teamrc.ai](https://teamrc.ai) or self-hosted) to sync changes across machines, VMs, and teammates in real time.

## Quick Start

```bash
# Create a new team config
npx @teamrc/cli init

# Or join an existing team
npx @teamrc/cli join <invite-code>

# Sync config into your installed AI tools
npx @teamrc/cli sync
```

For local-only use:

```bash
npx @teamrc/cli init --local
```

## How it works

```mermaid
---
config:
  flowchart:
    curve: linear
---
graph TD
    R["Teamrc Relay"] <--> A["Machine A"]
    R <--> B["Machine B"]
    R <--> C["CI / VM"]

    A --> A1["Claude Code\nGemini"]
    B --> B1["Cursor\nOpenClaw"]
    C --> C1["Codex\n..."]

    style R fill:#e0e7ff,stroke:#6366f1,color:#312e81
    style A fill:#f4f4f5,stroke:#a1a1aa,color:#27272a
    style B fill:#f4f4f5,stroke:#a1a1aa,color:#27272a
    style C fill:#f4f4f5,stroke:#a1a1aa,color:#27272a
    style A1 fill:#fff,stroke:#d4d4d8,color:#52525b
    style B1 fill:#fff,stroke:#d4d4d8,color:#52525b
    style C1 fill:#fff,stroke:#d4d4d8,color:#52525b
```

Each machine runs `teamrc sync` to write native files for its installed AI tools. The relay keeps `.teamrc.yaml`, skills, and shared knowledge in sync across all of them.

## Example

```yaml
name: my-team

members:
  - name: researcher
    role: Finds and summarizes relevant information
  - name: builder
    role: Implements and iterates on ideas

skills:
  - id: write-tests
    body: Always write tests for new functionality.
    alwaysApply: true
```

Then:

```bash
npx @teamrc/cli sync
```

And teamrc writes the right files for the tools you use.

## EXPERIMENTAL — Shared Task List

Agents can assign work to each other across machines and platforms. A Claude Code agent on your laptop can hand off a copywriting task to the OpenClaw copywriter on a VM.

```bash
# Create a task for another agent
teamrc task create "Write landing page copy" --assign copywriter

# See your tasks
teamrc task list --mine

# Claim and complete
teamrc task claim 1
teamrc task done 1
```

Enable real-time task sync in the daemon with `--experimental`:

```bash
teamrc daemon --experimental
```

This is under active development. The task commands work today; daemon auto-sync is experimental.

## Self-Hosting

```bash
docker compose up   # starts Postgres + relay at http://localhost:4000
```

Point the CLI at your relay with `TEAMRC_RELAY=http://localhost:4000` or set `relay:` in `.teamrc.yaml`.

See [docs/deploy-coolify.md](docs/deploy-coolify.md) for production deployment.

## Documentation

- **[Get Started](https://github.com/teamrc-ai/teamrc/wiki/Get-Started)** - Create a synced team in 2 minutes
- **[CLI Reference](https://github.com/teamrc-ai/teamrc/wiki/CLI-Reference)** - All commands with flags and examples
- **[Configuration](https://github.com/teamrc-ai/teamrc/wiki/Configuration)** - `.teamrc.yaml` format and options
- **[Platforms](https://github.com/teamrc-ai/teamrc/wiki/Platforms)** - How teamrc works on each AI platform
- **[Template Catalog](https://github.com/teamrc-ai/teamrc/wiki/Template-Catalog)** - 12 team templates, 68 agents, 49 skills
- **[Sharing & Access](https://github.com/teamrc-ai/teamrc/wiki/Sharing-&-Access)** - Public sharing, access roles, clone/fork
- **[Architecture](https://github.com/teamrc-ai/teamrc/wiki/Architecture)** - System design, auth, sync protocol
- **[API Reference](https://github.com/teamrc-ai/teamrc/wiki/API-Reference)** - REST and WebSocket API
