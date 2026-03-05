import * as crypto from "node:crypto";
import type { SyncChange } from "./relay-client.js";

function hashLine(line: string): string {
  return crypto.createHash("sha256").update(line).digest("hex").slice(0, 16);
}

export interface MergeResult {
  content: string;
  action: "keep-local" | "accept-remote" | "merged";
  warning?: string;
}

/**
 * Determine if a file key represents knowledge (append-only merge)
 * vs a definition file (last-write-wins).
 */
export function isKnowledgeKey(key: string): boolean {
  return key.startsWith("knowledge:");
}

/**
 * Merge knowledge files using append-only strategy.
 * Deduplicates entries by content hash. Both sides' entries are preserved.
 */
export function mergeKnowledge(local: string, remote: string): MergeResult {
  const localLines = local.split("\n");
  const remoteLines = remote.split("\n");

  // Build set of hashes for local content lines (skip empty/header lines)
  const localHashes = new Set<string>();
  for (const line of localLines) {
    const trimmed = line.trim();
    if (trimmed.length > 0) {
      localHashes.add(hashLine(trimmed));
    }
  }

  // Find remote lines not already in local
  const newLines: string[] = [];
  for (const line of remoteLines) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    if (!localHashes.has(hashLine(trimmed))) {
      newLines.push(line);
    }
  }

  if (newLines.length === 0) {
    return { content: local, action: "keep-local" };
  }

  // Append new entries to local content
  const merged = local.trimEnd() + "\n" + newLines.join("\n") + "\n";
  return { content: merged, action: "merged" };
}

/**
 * Resolve agent definition conflicts using last-write-wins.
 * Compares local modification time against remote timestamp.
 */
export function resolveDefinition(
  localContent: string,
  remoteChange: SyncChange,
  localModifiedAt: number,
): MergeResult {
  if (localContent === remoteChange.content) {
    return { content: localContent, action: "keep-local" };
  }

  if (remoteChange.updated_at > localModifiedAt) {
    return { content: remoteChange.content, action: "accept-remote" };
  }

  if (remoteChange.updated_at === localModifiedAt) {
    // Tie-break: accept remote (arbitrary but consistent)
    return {
      content: remoteChange.content,
      action: "accept-remote",
      warning: "Simultaneous edit detected on agent definition. Remote version accepted (last-write-wins tie-break).",
    };
  }

  // Local is newer — keep local
  return { content: localContent, action: "keep-local" };
}

/**
 * Resolve a single file change from the relay against local state.
 */
export function resolveChange(
  key: string,
  localContent: string | null,
  remoteChange: SyncChange,
  localModifiedAt: number,
): MergeResult {
  // If no local content, accept remote
  if (localContent === null) {
    return { content: remoteChange.content, action: "accept-remote" };
  }

  if (isKnowledgeKey(key)) {
    return mergeKnowledge(localContent, remoteChange.content);
  }

  return resolveDefinition(localContent, remoteChange, localModifiedAt);
}
