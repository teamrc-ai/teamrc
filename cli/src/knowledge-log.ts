import type * as p from "@clack/prompts";

/** Relay knowledge cap in bytes (100KB). */
export const KNOWLEDGE_CAP = 100_000;

/**
 * Log knowledge size when it exceeds 70% of the relay cap.
 *
 * - Above 90%: warn that auto-pruning will kick in
 * - 70%–90%: show current usage
 * - Below 70%: silent
 */
export function logKnowledgeSize(log: typeof p.log, sizeBytes: number): void {
  const pct = sizeBytes / KNOWLEDGE_CAP;
  const sizeKB = Math.round(sizeBytes / 1024);
  const capKB = Math.round(KNOWLEDGE_CAP / 1024);

  if (pct > 0.9) {
    log.warn(
      `Knowledge nearly full (${sizeKB}KB / ${capKB}KB). Oldest entries will be pruned automatically.`,
    );
  } else if (pct > 0.7) {
    log.info(`Knowledge: ${sizeKB}KB / ${capKB}KB`);
  }
  // Below 70%: don't show anything
}
