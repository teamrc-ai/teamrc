/**
 * Phoenix Channel client for Node.js.
 *
 * Implements the Phoenix channel wire protocol directly over the `ws` WebSocket
 * library. This avoids depending on the browser-oriented `phoenix` npm package
 * which does not reliably work in Node.js environments.
 *
 * Wire protocol: JSON arrays of [join_ref, ref, topic, event, payload]
 */

import WebSocket from "ws";
import { signMessage } from "./auth.js";

// ---------------------------------------------------------------------------
// Public interfaces
// ---------------------------------------------------------------------------

export interface KnowledgeChannelEvents {
  onUpdate: (content: string, hash: string, size: number) => void;
  onJoin: (hash: string, size: number, cap: number) => void;
  onError: (error: Error) => void;
  onClose: () => void;
}

export interface KnowledgeChannel {
  push(content: string): Promise<{ knowledge_hash: string; knowledge_size: number }>;
  leave(): void;
}

export interface TasksChannelEvents {
  onJoin: (tasks: TaskChannelItem[]) => void;
  onCreated: (task: TaskChannelItem) => void;
  onUpdated: (task: TaskChannelItem) => void;
  onError: (error: Error) => void;
  onClose: () => void;
}

export interface TaskChannelItem {
  number: number;
  description: string;
  assignee: string;
  status: string;
  created_by?: string;
  claimed_by?: string;
  claimed_at?: string;
  completed_at?: string;
  result?: string;
  inserted_at?: string;
  updated_at?: string;
}

export interface TasksChannel {
  leave(): void;
}

/** Validate and cap fields on a task item received from the relay. */
function sanitizeTaskItem(raw: unknown): TaskChannelItem | null {
  if (!raw || typeof raw !== "object") return null;
  const t = raw as Record<string, unknown>;
  if (typeof t.number !== "number") return null;
  if (typeof t.description !== "string") return null;
  if (typeof t.assignee !== "string") return null;
  return {
    number: t.number,
    description: t.description.slice(0, 2000),
    assignee: t.assignee.slice(0, 64),
    status: typeof t.status === "string" ? t.status.slice(0, 20) : "unknown",
    ...(typeof t.created_by === "string" ? { created_by: t.created_by.slice(0, 128) } : {}),
    ...(typeof t.claimed_by === "string" ? { claimed_by: t.claimed_by.slice(0, 128) } : {}),
    ...(typeof t.claimed_at === "string" ? { claimed_at: t.claimed_at.slice(0, 30) } : {}),
    ...(typeof t.completed_at === "string" ? { completed_at: t.completed_at.slice(0, 30) } : {}),
    ...(typeof t.result === "string" ? { result: t.result.slice(0, 10_000) } : {}),
    ...(typeof t.inserted_at === "string" ? { inserted_at: t.inserted_at.slice(0, 30) } : {}),
    ...(typeof t.updated_at === "string" ? { updated_at: t.updated_at.slice(0, 30) } : {}),
  };
}

export interface ChannelClient {
  connect(): Promise<void>;
  joinKnowledge(teamId: string, events: KnowledgeChannelEvents): Promise<KnowledgeChannel>;
  joinTasks(teamId: string, events: TasksChannelEvents): Promise<TasksChannel>;
  disconnect(): void;
  isConnected(): boolean;
}

// ---------------------------------------------------------------------------
// Ticket generation
// ---------------------------------------------------------------------------

/**
 * Generate a signed socket ticket for Phoenix WebSocket authentication.
 *
 * Format: `<timestamp>.<token>.<signature>`
 * The signed message is `<timestamp>.<token>`.
 */
export async function generateSocketTicket(
  privateKey: Uint8Array,
  token: string,
): Promise<string> {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.${token}`;
  const signature = await signMessage(privateKey, message);
  return `${timestamp}.${token}.${signature}`;
}

// ---------------------------------------------------------------------------
// URL conversion
// ---------------------------------------------------------------------------

/**
 * Convert an HTTP(S) relay URL to a WebSocket URL for the Phoenix socket
 * endpoint.
 *
 * - `https://example.com`    -> `wss://example.com/socket`
 * - `http://localhost:4000`  -> `ws://localhost:4000/socket`
 * - Trailing slashes are stripped before appending `/socket`.
 */
export function relayUrlToSocketUrl(relayUrl: string): string {
  const stripped = relayUrl.replace(/\/+$/, "");
  const wsUrl = stripped
    .replace(/^https:\/\//i, "wss://")
    .replace(/^http:\/\//i, "ws://");
  return `${wsUrl}/socket`;
}

// ---------------------------------------------------------------------------
// Phoenix wire protocol helpers
// ---------------------------------------------------------------------------

type PhoenixMessage = [
  joinRef: string | null,
  ref: string | null,
  topic: string,
  event: string,
  payload: Record<string, unknown>,
];

let refCounter = 0;
function nextRef(): string {
  refCounter += 1;
  return String(refCounter);
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/**
 * Error returned when a Phoenix channel reply has a non-ok status.
 * The `reason` field contains the server-provided reason string (e.g.
 * "unmatched topic", "unauthorized") for programmatic detection.
 */
export class ChannelReplyError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(`Channel reply error: ${reason}`);
    this.name = "ChannelReplyError";
    this.reason = reason;
  }
}

// ---------------------------------------------------------------------------
// Channel client factory
// ---------------------------------------------------------------------------

export function createChannelClient(
  relayUrl: string,
  privateKey: Uint8Array,
  token: string,
): ChannelClient {
  let socket: WebSocket | null = null;
  let connected = false;
  let heartbeatTimer: ReturnType<typeof setInterval> | null = null;

  // Pending reply handlers keyed by ref
  const pendingReplies = new Map<
    string,
    { resolve: (payload: Record<string, unknown>) => void; reject: (err: Error) => void; timer: ReturnType<typeof setTimeout> }
  >();

  // Event handlers keyed by topic+event
  const eventHandlers = new Map<string, (payload: Record<string, unknown>) => void>();

  // Track join refs for channel replies
  const joinRefs = new Map<string, string>(); // topic -> joinRef

  function handleMessage(raw: string): void {
    let msg: PhoenixMessage;
    try {
      msg = JSON.parse(raw) as PhoenixMessage;
    } catch {
      return; // Not valid JSON  --  ignore
    }

    const [joinRef, ref, topic, event, payload] = msg;

    // Handle replies to our pushes
    if (event === "phx_reply" && ref) {
      const pending = pendingReplies.get(ref);
      if (pending) {
        clearTimeout(pending.timer);
        pendingReplies.delete(ref);
        const response = payload.response as Record<string, unknown> | undefined;
        if (payload.status === "ok") {
          pending.resolve(response ?? {});
        } else {
          const reason = (response as Record<string, unknown> | undefined)?.reason ?? payload.status;
          pending.reject(new ChannelReplyError(String(reason)));
        }
      }
      return;
    }

    // Handle phx_error for a channel
    if (event === "phx_error") {
      const key = `${topic}:error`;
      const handler = eventHandlers.get(key);
      if (handler) handler(payload);
      return;
    }

    // Handle phx_close for a channel
    if (event === "phx_close") {
      const key = `${topic}:close`;
      const handler = eventHandlers.get(key);
      if (handler) handler(payload);
      return;
    }

    // Handle custom events (e.g. knowledge:updated)
    const key = `${topic}:${event}`;
    const handler = eventHandlers.get(key);
    if (handler) handler(payload);
  }

  function startHeartbeat(): void {
    // Phoenix expects heartbeat messages every 30 seconds
    heartbeatTimer = setInterval(() => {
      if (socket && socket.readyState === WebSocket.OPEN) {
        const ref = nextRef();
        const msg: PhoenixMessage = [null, ref, "phoenix", "heartbeat", {}];
        socket.send(JSON.stringify(msg));
      }
    }, 30_000);
  }

  function stopHeartbeat(): void {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
  }

  function sendMessage(
    joinRef: string | null,
    topic: string,
    event: string,
    payload: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    return new Promise((resolve, reject) => {
      if (!socket || socket.readyState !== WebSocket.OPEN) {
        reject(new Error("Socket is not connected"));
        return;
      }

      const ref = nextRef();

      const msg: PhoenixMessage = [joinRef, ref, topic, event, payload];
      socket.send(JSON.stringify(msg));

      // Timeout pending replies after 15 seconds
      const timer = setTimeout(() => {
        if (pendingReplies.has(ref)) {
          pendingReplies.delete(ref);
          reject(new Error(`Channel push timed out for ${event} on ${topic}`));
        }
      }, 15_000);

      pendingReplies.set(ref, { resolve, reject, timer });
    });
  }

  return {
    async connect(): Promise<void> {
      const ticket = await generateSocketTicket(privateKey, token);
      const wsUrl = relayUrlToSocketUrl(relayUrl);
      const urlWithParams = `${wsUrl}/websocket?ticket=${encodeURIComponent(ticket)}&vsn=2.0.0`;

      return new Promise<void>((resolve, reject) => {
        socket = new WebSocket(urlWithParams);

        socket.on("open", () => {
          connected = true;
          startHeartbeat();
          resolve();
        });

        socket.on("message", (data) => {
          handleMessage(data.toString());
        });

        socket.on("close", () => {
          connected = false;
          stopHeartbeat();
          // Reject all pending replies and clear their timers
          for (const [ref, pending] of pendingReplies) {
            clearTimeout(pending.timer);
            pending.reject(new Error("Socket closed"));
            pendingReplies.delete(ref);
          }
        });

        socket.on("error", (err) => {
          if (!connected) {
            reject(new Error(`WebSocket connection failed: ${err.message}`));
          }
        });
      });
    },

    async joinKnowledge(
      teamId: string,
      events: KnowledgeChannelEvents,
    ): Promise<KnowledgeChannel> {
      const topic = `knowledge:${teamId}`;
      const joinRef = nextRef();

      // Register event handlers before joining
      eventHandlers.set(`${topic}:knowledge:updated`, (payload) => {
        events.onUpdate(
          String(payload.content ?? ""),
          String(payload.knowledge_hash ?? ""),
          Number(payload.knowledge_size ?? 0),
        );
      });

      eventHandlers.set(`${topic}:error`, (payload) => {
        events.onError(new Error(`Channel error: ${JSON.stringify(payload)}`));
      });

      eventHandlers.set(`${topic}:close`, () => {
        events.onClose();
      });

      joinRefs.set(topic, joinRef);

      // Send join message
      const reply = await sendMessage(joinRef, topic, "phx_join", {});

      events.onJoin(
        String(reply.knowledge_hash ?? ""),
        Number(reply.knowledge_size ?? 0),
        Number(reply.knowledge_cap ?? 100_000),
      );

      return {
        async push(content: string): Promise<{ knowledge_hash: string; knowledge_size: number }> {
          const reply = await sendMessage(
            joinRefs.get(topic) ?? null,
            topic,
            "knowledge:push",
            { content },
          );
          return {
            knowledge_hash: String(reply.knowledge_hash ?? ""),
            knowledge_size: Number(reply.knowledge_size ?? 0),
          };
        },

        leave(): void {
          if (socket && socket.readyState === WebSocket.OPEN) {
            const ref = nextRef();
            const msg: PhoenixMessage = [joinRefs.get(topic) ?? null, ref, topic, "phx_leave", {}];
            socket.send(JSON.stringify(msg));
          }
          eventHandlers.delete(`${topic}:knowledge:updated`);
          eventHandlers.delete(`${topic}:error`);
          eventHandlers.delete(`${topic}:close`);
          joinRefs.delete(topic);
        },
      };
    },

    async joinTasks(
      teamId: string,
      events: TasksChannelEvents,
    ): Promise<TasksChannel> {
      const topic = `tasks:${teamId}`;
      const joinRef = nextRef();

      // Register event handlers before joining
      eventHandlers.set(`${topic}:tasks:created`, (payload) => {
        const task = sanitizeTaskItem(payload.task);
        if (task) events.onCreated(task);
      });

      eventHandlers.set(`${topic}:tasks:updated`, (payload) => {
        const task = sanitizeTaskItem(payload.task);
        if (task) events.onUpdated(task);
      });

      eventHandlers.set(`${topic}:error`, (payload) => {
        events.onError(new Error(`Tasks channel error: ${JSON.stringify(payload)}`));
      });

      eventHandlers.set(`${topic}:close`, () => {
        events.onClose();
      });

      joinRefs.set(topic, joinRef);

      // Send join message
      const reply = await sendMessage(joinRef, topic, "phx_join", {});

      const rawTasks = Array.isArray(reply.tasks) ? reply.tasks : [];
      events.onJoin(
        rawTasks.map(sanitizeTaskItem).filter((t): t is TaskChannelItem => t !== null),
      );

      return {
        leave(): void {
          if (socket && socket.readyState === WebSocket.OPEN) {
            const ref = nextRef();
            const msg: PhoenixMessage = [joinRefs.get(topic) ?? null, ref, topic, "phx_leave", {}];
            socket.send(JSON.stringify(msg));
          }
          eventHandlers.delete(`${topic}:tasks:created`);
          eventHandlers.delete(`${topic}:tasks:updated`);
          eventHandlers.delete(`${topic}:error`);
          eventHandlers.delete(`${topic}:close`);
          joinRefs.delete(topic);
        },
      };
    },

    disconnect(): void {
      stopHeartbeat();
      if (socket) {
        connected = false;
        socket.close();
        socket = null;
      }
      pendingReplies.clear();
      eventHandlers.clear();
      joinRefs.clear();
    },

    isConnected(): boolean {
      return connected && socket !== null && socket.readyState === WebSocket.OPEN;
    },
  };
}
