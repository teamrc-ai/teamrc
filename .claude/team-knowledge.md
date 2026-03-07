# Team Knowledge

## 2026-03-07: CLI new commands and sync modes (frontend-dev)

Added CLI-side support for new backend endpoints and features:

### New client methods (`cli/src/client.ts`)
- `previewByInvite(inviteCode)` — calls `POST /api/teams/preview`, returns team without joining
- `createInvite(ttlHours)` — calls `POST /api/teams/invite`, returns `{invite_code, expires_at}`
- `SyncChange` interface now includes optional `pushed_by` field

### New CLI commands (`cli/src/index.ts`)
- `teamrc clone <invite-code>` — preview a team and copy it locally without joining the relay. Does NOT save teamId to config or prompt for account linking.
- `teamrc invite` — create an invite code for current team (default TTL: 24h)
- `teamrc whoami` — show local identity (token, machine, account, team, relay, platform). No network calls.

### `--no-sync` flag on `join`
- Commander parses `--no-sync` as `opts.sync === false`
- Saves `noSync: true` to config, skips account linking prompt

### Daemon sync modes (`cli/src/daemon.ts`)
- New `syncMode` option: `"all"` | `"knowledge"` | `"none"` (default: `"knowledge"`)
- `"knowledge"` — only sync keys starting with `knowledge:`
- `"none"` — log changes but write nothing
- `"all"` — original behavior
- Both `applyRemoteChanges` and `doPushChanges` respect the filter
- Existing daemon tests updated to pass `syncMode: "all"` to preserve behavior

### Config change (`cli/src/config.ts`)
- `TeamrcConfig` now has optional `noSync?: boolean` field
