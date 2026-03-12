#!/bin/bash
# Section 7: Multi-Platform Cross-Sync
# Usage: bash scripts/verify/section-07-cross-sync.sh
#
# Run AFTER: npx teamrc init --platform claude-code,cursor,codex,gemini,openclaw
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Section 7: Multi-Platform Cross-Sync"

subsection "7.1: All platforms have agents"
check_file ".claude/agents/trc-agent.md" "Claude Code: .claude/agents/trc-agent.md"
check_file ".cursor/agents/trc-agent.md" "Cursor: .cursor/agents/trc-agent.md"
check_file ".codex/agents/trc-agent.toml" "Codex: .codex/agents/trc-agent.toml (TOML)"
check_file ".gemini/agents/trc-agent.md" "Gemini: .gemini/agents/trc-agent.md"
check_dir "$HOME/.openclaw/workspaces/trc-agent" "OpenClaw: ~/.openclaw/workspaces/trc-agent/"

subsection "7.1: Routing files"
check_contains "CLAUDE.md" "<!-- teamrc -->" "CLAUDE.md routing"
if [ -f ".cursor/AGENTS.md" ]; then
  check_contains ".cursor/AGENTS.md" "<!-- teamrc -->" "Cursor AGENTS.md routing"
fi
check_contains "AGENTS.md" "<!-- teamrc -->" "Codex AGENTS.md routing"
check_contains "GEMINI.md" "<!-- teamrc -->" "Gemini GEMINI.md routing"

summary
