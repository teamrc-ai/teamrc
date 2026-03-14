# Knowledge Daemon via Phoenix Channels

**Date:** 2026-03-14
**Status:** Proposed
**Scope:** CLI daemon rewrite, Phoenix channels, knowledge pruning

---

## Problem

Team knowledge — a shared markdown file where agents record findings — has two issues:

### 1. Knowledge doesn't sync automatically

The daemon (`cli/src/daemon.ts`) is disabled and polls the entire team definition via REST every 2 minutes. Knowledge changes made by agents sit locally until someone runs `teamrc push` or `teamrc sync`. On a multi-machine team, Machine B doesn't see Machine A's findings until both manually sync.

### 2. No cap handling

The relay caps knowledge at 100KB (~2,000-2,500 lines). When the cap is hit:
- REST push returns a 422 — the CLI shows a vague error
- The daemon logs a warning and skips the write
- Sync silently stops working
- There is no visibility into current size, no warning as it approaches the limit, and no recovery path

---

## Solution

### Repurpose the daemon for knowledge-only sync over Phoenix Channels

The daemon becomes a lightweight background process that keeps the knowledge file in sync across machines in real-time. It does **not** sync team config (members, skills, name) — those remain explicit via `push`/`pull`/`sync`.

### FIFO pruning when the cap is reached

Parse knowledge into sections. When over cap, drop oldest sections first. The preamble (first ~10 lines) is permanent and never dropped.

---

## Architecture

### Knowledge file structure

```markdown
# Team Knowledge                          ← preamble line 1

Shared findings and decisions.            ← preamble line 2-3

CLI tests: cd cli && npm test             ← preamble line 4
Elixir tests: cd teamrc && mix test       ← preamble line 5

## Database indexing                      ← section 1 (oldest, dropped first)
Found that the users table needs a
composite index on (token_id, team_id).

## Auth token format                      ← section 2
The trc_ak_ prefix encodes the public
key in base64url.

## CI flakiness                           ← section 3 (newest, dropped last)
The daemon E2E tests fail on slow CI
runners due to a 5s timeout.
```

**Preamble**: Everything before the first `## ` heading, up to 10KB. This is permanent — never dropped during pruning. ~50 lines of core knowledge: test commands, architecture notes, key conventions. The 10KB allocation comes out of the 100KB relay cap, leaving 90KB for FIFO sections.

**Sections**: Each `## <heading>` plus all lines until the next `## ` or EOF. Sections are ordered chronologically (oldest at top, newest at bottom — natural result of append-only writes). Sections are the unit of FIFO eviction.

### Pruning

Pruning is **not daemon-specific** — it happens wherever knowledge is merged. All paths that merge knowledge (push, pull, sync, daemon, channel) go through the same merge+prune flow:

1. Merge remote + local knowledge (existing `mergeKnowledge`)
2. If merged content exceeds 100KB: parse into preamble + sections
3. Drop sections from the top (oldest first) until total size is under 80KB
4. Reassemble: preamble + remaining sections
5. Write/push the pruned result

The prune function is a pure utility (`pruneKnowledge(content, maxBytes)`) called after every merge. No special daemon logic needed.

No summarization, no pinning, no heuristics. Just FIFO. Revisit if user demand emerges for pinned/core sections.

The 80KB target (not 100KB) leaves ~20KB headroom so the next few agent writes don't immediately trigger another prune cycle.

### Message flow

```
Machine A                    Relay (Phoenix)              Machine B
─────────                    ───────────────              ─────────
agent appends to
knowledge file
    │
chokidar detects ──ws──►  knowledge:push
                             │
                             merge with DB
                             prune if > 100KB
                             persist
                             │
                             broadcast ──────ws──────►  knowledge:updated
                                                          │
                                                          merge with local
                                                          write to file
```

### Phoenix Socket auth

The CLI generates a signed **ticket** for WebSocket authentication:

```
Format:  <timestamp>.<token>.<signature>
Message: <timestamp>.<token>
Signed:  Ed25519 with machine private key
TTL:     30 seconds
```

The server's `UserSocket.connect/3` parses the ticket, validates the timestamp, extracts the public key from the token (`trc_ak_<base64url(pubkey)>`), and verifies the Ed25519 signature. This reuses the exact same auth infrastructure as the REST API — no new crypto, no sessions.

### Channel protocol

**Topic:** `knowledge:<team_id>`

**Join reply:**
```json
{
  "knowledge_hash": "abc123...",
  "knowledge_size": 42000,
  "knowledge_cap": 100000
}
```

**Client → Server: `knowledge:push`**
```json
{ "content": "...full knowledge content..." }
```

Server merges with DB content, prunes if over cap, persists, broadcasts to other clients on the topic. Replies with:
```json
{ "ok": true, "knowledge_hash": "def456...", "knowledge_size": 45000 }
```

**Server → Client: `knowledge:updated`**
```json
{
  "content": "...merged knowledge content...",
  "knowledge_hash": "def456...",
  "knowledge_size": 45000
}
```

### Anti-echo

When the daemon writes the knowledge file after receiving a remote update, chokidar fires. To avoid pushing back what we just received:

- Track `lastWrittenHash` = SHA-256 of the content we last wrote to disk
- On chokidar change: compute hash of new file content. If it matches `lastWrittenHash`, skip the push

Uses the same hash normalization as `ContentHash.compute_knowledge_hash` (trailing newline normalized).

### Transport fallback

Phoenix handles transport fallback natively — the `phoenix` JS client tries WebSocket first, then falls back to longpoll automatically. Both transports use the same channel API, so the daemon code doesn't need to know which transport is active.

The daemon retains a last-resort REST polling mode for cases where the server is completely unreachable via both WebSocket and longpoll (e.g., server down, network partition). This is not the primary fallback mechanism — Phoenix longpoll handles transport-level issues transparently.

### PubSub for REST-initiated changes

When knowledge is updated via REST (`teamrc push`, `teamrc sync`, web UI), broadcast through PubSub so WebSocket-connected daemons are notified immediately:

```elixir
Phoenix.PubSub.broadcast(Teamrc.PubSub, "team_knowledge:#{team_id}", {
  :knowledge_updated,
  %{content: merged, knowledge_hash: hash, source_token: token}
})
```

The channel's `handle_info` receives this and pushes to connected clients (excluding the source token to prevent echo).

---

## Implementation

### Phase 1: Knowledge utilities (CLI)

Add section-aware parsing and pruning to `cli/src/team-yaml.ts`:

```typescript
interface KnowledgeSection {
  heading: string;
  body: string;    // includes the ## heading line
}

interface ParsedKnowledge {
  preamble: string;   // # title + first 10 lines
  sections: KnowledgeSection[];  // ordered oldest → newest
}

function parseKnowledge(content: string): ParsedKnowledge;
function pruneKnowledge(content: string, maxBytes: number): string;
```

`pruneKnowledge(content, 100_000)` preserves the preamble (up to 10KB) and drops oldest sections until total size ≤ 80,000 bytes. Returns the pruned content with preamble intact.

Also add to `content_hash.ex`:

```elixir
@spec prune_knowledge(String.t(), non_neg_integer()) :: String.t()
def prune_knowledge(content, max_bytes \\ 100_000)
```

Identical logic, both implementations tested against the same fixtures.

**Tests:**
- Parse empty content → empty preamble, no sections
- Parse preamble-only content → preamble preserved, no sections
- Parse content with sections → correct split
- Preamble capped at 10KB
- Prune with content under cap → no change
- Prune with content over cap → oldest sections dropped, preamble intact
- Prune preserves section boundaries (no partial section removal)

### Phase 2: Backend — Socket, Channel, knowledge update

**New files:**
- `teamrc/lib/teamrc_web/channels/user_socket.ex` — ticket auth
- `teamrc/lib/teamrc_web/channels/knowledge_channel.ex` — join, knowledge:push, PubSub handler

**Modified files:**
- `teamrc/lib/teamrc_web/endpoint.ex` — add `socket "/socket", TeamrcWeb.UserSocket, websocket: true, longpoll: true` (Phoenix handles WebSocket → longpoll fallback transparently)
- `teamrc/lib/teamrc/teams.ex` — add `update_knowledge/3` (merge, prune, persist, PubSub broadcast)
- `teamrc/lib/teamrc/teams.ex` — add PubSub broadcast in `do_update_team` for REST-initiated knowledge changes

**`update_knowledge/3` flow:**
1. Verify token access via `resolve_team_id`
2. Fetch current team knowledge from DB
3. `ContentHash.merge_knowledge(existing, incoming)`
4. `ContentHash.prune_knowledge(merged, 100_000)` if over cap
5. Compute new `knowledge_hash`
6. Persist via `Repo.update`
7. PubSub broadcast `{:knowledge_updated, %{content, knowledge_hash, knowledge_size, source_token}}`
8. Return `{:ok, merged_content, knowledge_hash, knowledge_size}`

**Channel rate limiting:** Max 1 `knowledge:push` per second per socket. Drop with `{:reply, {:error, %{reason: "rate_limited"}}, socket}`.

**Tests:**
- Socket: valid ticket connects, expired ticket rejected, wrong signature rejected
- Channel: join with valid token, join with wrong team_id rejected
- Channel: knowledge:push merges and broadcasts
- Channel: knowledge:push with oversized content triggers prune
- Channel: PubSub from REST push forwarded to connected clients
- Channel: rate limiting enforced

### Phase 3: CLI — Channel client

**New file:** `cli/src/channel-client.ts`

Wraps the `phoenix` npm package for Node.js:

```typescript
interface ChannelClient {
  connect(): Promise<void>;
  joinKnowledge(teamId: string): Promise<KnowledgeChannel>;
  disconnect(): void;
  onDisconnect(cb: () => void): void;
}

interface KnowledgeChannel {
  push(content: string): Promise<{ knowledge_hash: string; knowledge_size: number }>;
  onUpdate(cb: (content: string, hash: string, size: number) => void): void;
  leave(): void;
}
```

**Dependencies:** Add `phoenix` (^1.7) and `ws` (^8.0) to `cli/package.json`. The `phoenix` Socket accepts a `transport` option — pass `WebSocket` from `ws`.

URL conversion: `https://teamrc.ai` → `wss://teamrc.ai/socket`, `http://localhost:4000` → `ws://localhost:4000/socket`.

**Tests:**
- Ticket generation format and signature
- URL conversion (http→ws, https→wss, with/without trailing slash)

### Phase 4: CLI — Daemon rewrite

**Rewrite:** `cli/src/daemon.ts`

```typescript
export interface KnowledgeDaemonOptions {
  relayUrl: string;
  privateKey: Uint8Array;
  token: string;
  teamId: string;
  teamSlug: string;
  scope: TeamScope;
  adapters: PlatformAdapter[];
  platforms: string[];
  fallbackPollInterval?: number;  // default 120s
}

export function startKnowledgeDaemon(opts: KnowledgeDaemonOptions): { stop: () => void };
```

**WebSocket mode:**
1. Connect socket, join `knowledge:<teamId>`
2. Compare join reply `knowledge_hash` with local — merge if different
3. Watch knowledge file(s) via chokidar (debounce 500ms)
4. Local change → hash check (anti-echo) → push via channel
5. Remote `knowledge:updated` → merge with local → write to all adapters → update `lastWrittenHash`

**REST last-resort fallback mode:**
1. Activated when WebSocket/longpoll connection fails (server unreachable)
2. Poll `knowledge_hash` via `/head` endpoint every `fallbackPollInterval`
3. On local change: debounce → push knowledge via REST
4. On reconnect: switch back to WebSocket mode

**Size warnings (logged to console):**
- `>70%`: `[hh:mm:ss] Knowledge: 72KB / 100KB`
- `>90%`: `[hh:mm:ss] WARN: Knowledge nearly full (93KB / 100KB). Oldest entries will be pruned on next sync.`

**Modify:** `cli/src/commands/daemon.ts` — update options, remove team-config sync concerns.

**Uncomment:** `cli/src/index.ts` — enable daemon registration.

**Tests:**
- WebSocket mode: local change triggers push
- WebSocket mode: remote update triggers local merge + write
- Anti-echo: local write from remote update does not trigger push
- REST fallback: activates on connection failure
- Size warnings at thresholds
- Prune triggered on oversized merge

### Phase 5: Size reporting in existing commands

Add knowledge size display to `push`, `pull`, `sync` commands when knowledge is >70% of cap:

```
✓ Pushed team (6 agents, 3 skills)
  Knowledge: 74KB / 100KB
```

At >90%:
```
⚠ Knowledge nearly full (93KB / 100KB). Oldest entries will be pruned automatically.
```

After a prune event:
```
⚠ Knowledge pruned: dropped 12 oldest entries to fit within 100KB relay limit.
```

---

## Decisions

| Decision | Rationale |
|----------|-----------|
| Knowledge-only daemon | Team config changes are infrequent and admin-initiated. Knowledge benefits most from real-time sync. Simpler daemon, fewer edge cases. |
| Phoenix Channels over REST polling | Sub-second propagation for knowledge. Eliminates wasted polls. PubSub infrastructure already running. |
| Phoenix longpoll as primary fallback | Phoenix handles WebSocket → longpoll fallback transparently. Same channel API, zero extra code. REST polling retained as last-resort fallback when the server is completely unreachable. |
| Ticket auth (not per-message signing) | WebSocket is a persistent TLS-encrypted connection. Once authenticated at connect time, all messages are encrypted and integrity-protected by TLS — per-message Ed25519 signing would be redundant. REST needs per-request signing because HTTP requests are stateless. Standard practice (Slack, Discord, Firebase, LiveView). Enforce `wss://` in production; allow `ws://` only for localhost. |
| Full content in channel messages | Knowledge is bounded at 100KB — well within WebSocket frame limits. Simpler than diffing or hash-then-fetch. |
| Server-side merge | Single source of truth. Avoids split-brain when two machines push simultaneously. |
| FIFO section pruning | Simple, deterministic, no external dependencies. Oldest knowledge is least relevant. |
| 10KB permanent preamble | Teams need a protected area for essentials (test commands, conventions). 10KB (~50 lines) is enough for core knowledge without eating too much of the 100KB cap. |
| Prune sections to ~72KB (80% of 90KB budget) | 10KB preamble + 90KB sections = 100KB cap. Pruning to 80% of the section budget prevents prune-on-every-push when near the cap. |
| Rate limit 1 push/sec | Prevents buggy file watcher or runaway agent from flooding the channel. |
| No pinning/core mechanism yet | FIFO is sufficient to start. Add `[core]` section pinning later if users need more control over what persists. |

---

## Out of Scope

- Knowledge summarization / LLM-assisted compaction
- Section pinning (`[core]` tags) — revisit later
- Cross-team knowledge sharing
- Section-aware merge (dedup by heading) — current line-based merge is sufficient
- `teamrc knowledge` subcommand (list, prune, compact)
- Daemon auto-start / launchd / systemd integration
- Multi-team global daemon (single team per daemon instance for now)

---

## Security

### Transport security
- **Production**: Enforce `wss://` (TLS). Reject `ws://` connections from non-localhost origins.
- **Development**: Allow `ws://` for `localhost` / `127.0.0.1` only.

### Ticket auth threat model
- **Replay**: 30s TTL on tickets. Server rejects expired tickets.
- **Theft**: Ticket is transmitted once in the WebSocket upgrade request (query param over TLS). Cannot be extracted from subsequent messages.
- **Session hijack**: Requires breaking TLS. At that point, per-message signing wouldn't help either — attacker could steal the private key.
- **BOLA**: Channel `join` verifies the token has access to the requested `team_id` via `resolve_team_id` (same check as REST API).

### Rate limiting
- `knowledge:push`: Max 1 per second per socket. Prevents runaway file watchers or buggy clients from flooding the server.
- **Per-token rate limiting via ETS**: Rate limits are tracked per token (not per socket) using an ETS table. This prevents a single token from bypassing rate limits by opening multiple connections.
- Socket connections: Standard Phoenix connection limits apply.

### Concurrent merge safety
- **SELECT FOR UPDATE**: The `update_knowledge/3` function uses `SELECT FOR UPDATE` to lock the team row during knowledge merges. This prevents race conditions when two machines push simultaneously -- without it, one machine's merge could silently overwrite the other's changes.

### Input validation
- **is_binary guard on content**: The `knowledge:push` handler validates that the `content` field is a binary string before processing. This prevents crashes from malformed payloads (e.g., `null`, integers, or nested objects sent as content).

### Phase 6: Security review
After implementation is complete, conduct a security review:
- Red team review of the channel auth flow (ticket generation, validation, TTL)
- BOLA/IDOR testing on channel join (can token A join token B's team?)
- Rate limit bypass testing (especially per-token ETS limits across multiple sockets)
- WebSocket frame size limits (prevent oversized payloads)
- Reconnection auth (ensure reconnect requires fresh ticket, not cached auth)
- Input validation on `knowledge:push` content (size, encoding, null bytes)
