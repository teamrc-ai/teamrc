#!/bin/bash
# Section 7: Multi-Platform Cross-Sync
# Usage: bash scripts/verify/section-07-cross-sync.sh
#
# Run AFTER: npx @teamrc/cli init --platform claude-code,cursor,codex,gemini,openclaw
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Section 7: Multi-Platform Cross-Sync"

subsection "7.1: All platforms have agents"
check_glob ".claude/agents/trc-*.md" "Claude Code: .claude/agents/trc-*.md"
check_glob ".cursor/agents/trc-*.md" "Cursor: .cursor/agents/trc-*.md"
check_glob ".codex/agents/trc-*.toml" "Codex: .codex/agents/trc-*.toml"
check_glob ".gemini/agents/trc-*.md" "Gemini: .gemini/agents/trc-*.md"
check_glob "$HOME/.openclaw/agents/trc-*.md" "OpenClaw: ~/.openclaw/agents/trc-*.md"

# Negative: no legacy OpenClaw workspaces
check_no_glob "$HOME/.openclaw/workspaces/trc-*" "No legacy OpenClaw workspaces"

subsection "7.2: Routing files"
check_contains "CLAUDE.md" "<!-- teamrc -->" "CLAUDE.md routing"
if [ -f ".cursor/AGENTS.md" ]; then
  check_contains ".cursor/AGENTS.md" "<!-- teamrc -->" "Cursor AGENTS.md routing"
fi
check_contains "AGENTS.md" "<!-- teamrc -->" "Codex AGENTS.md routing"
check_contains "GEMINI.md" "<!-- teamrc -->" "Gemini GEMINI.md routing"

subsection "7.3: Team membership consistency"
# All platforms should have the same number of trc-* agent files
CC_COUNT=$(ls .claude/agents/trc-*.md 2>/dev/null | wc -l | tr -d ' ')
CU_COUNT=$(ls .cursor/agents/trc-*.md 2>/dev/null | wc -l | tr -d ' ')
CX_COUNT=$(ls .codex/agents/trc-*.toml 2>/dev/null | wc -l | tr -d ' ')
GM_COUNT=$(ls .gemini/agents/trc-*.md 2>/dev/null | wc -l | tr -d ' ')
OC_COUNT=$(ls "$HOME/.openclaw/agents"/trc-*.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$CC_COUNT" -eq "$CU_COUNT" ] && [ "$CC_COUNT" -eq "$CX_COUNT" ] && [ "$CC_COUNT" -eq "$GM_COUNT" ] && [ "$CC_COUNT" -eq "$OC_COUNT" ]; then
  check "All platforms have same agent count ($CC_COUNT)" 0
else
  check "All platforms have same agent count (cc=$CC_COUNT cu=$CU_COUNT cx=$CX_COUNT gm=$GM_COUNT oc=$OC_COUNT)" 1
fi

summary
