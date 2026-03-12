#!/bin/bash
# Section 1: Fresh Install — verify state after init
# Usage: bash scripts/verify/section-01-fresh-install.sh [single|multi]
#   single — verify after: npx teamrc init --platform claude-code
#   multi  — verify after: npx teamrc init --platform claude-code,cursor,codex,gemini
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

MODE="${1:-single}"

section "Section 1: Fresh Install ($MODE)"

# --- 1.2 / 1.3: Post-init checks ---
subsection "Config & YAML"
check_file "$HOME/.teamrc/config.json" "~/.teamrc/config.json exists"
check_valid_json "$HOME/.teamrc/config.json" "~/.teamrc/config.json is valid JSON"
check_contains "$HOME/.teamrc/config.json" '"token"' "config has token"
check_contains "$HOME/.teamrc/config.json" '"relay"' "config has relay"
check_not_contains "$HOME/.teamrc/config.json" '"teamId"' "config has NO top-level teamId"

check_file ".teamrc.yaml" ".teamrc.yaml exists"
check_contains ".teamrc.yaml" "name:" ".teamrc.yaml has name"
check_contains ".teamrc.yaml" "members:" ".teamrc.yaml has members"
check_contains ".teamrc.yaml" "teamId:" ".teamrc.yaml has teamId"
check_contains ".teamrc.yaml" "platforms:" ".teamrc.yaml has platforms"

subsection "Keypair"
check_file "$HOME/.teamrc/key" "~/.teamrc/key exists"

# --- Platform-specific checks ---
subsection "Claude Code"
check_file ".claude/agents/trc-agent.md" "Claude Code agent file exists"
check_contains ".claude/agents/trc-agent.md" "name:" "agent has YAML frontmatter (name)"
check_contains ".claude/agents/trc-agent.md" "description:" "agent has YAML frontmatter (description)"
check_file "CLAUDE.md" "CLAUDE.md exists"
check_contains "CLAUDE.md" "<!-- teamrc -->" "CLAUDE.md has teamrc start marker"
check_contains "CLAUDE.md" "<!-- /teamrc -->" "CLAUDE.md has teamrc end marker"

if [ "$MODE" = "multi" ]; then
  subsection "Cursor"
  check_file ".cursor/agents/trc-agent.md" "Cursor agent file exists (.md)"
  check_contains ".cursor/agents/trc-agent.md" "name:" "Cursor agent has YAML frontmatter"
  if [ -f ".cursor/AGENTS.md" ]; then
    check_contains ".cursor/AGENTS.md" "<!-- teamrc -->" "Cursor AGENTS.md has teamrc marker"
  else
    skip "Cursor AGENTS.md marker" "file not created"
  fi

  subsection "Codex (TOML format)"
  check_file ".codex/agents/trc-agent.toml" "Codex agent file exists (.toml)"
  check_contains ".codex/agents/trc-agent.toml" "developer_instructions" "Codex agent has developer_instructions"
  check_contains ".codex/agents/trc-agent.toml" "# teamrc agent:" "Codex agent has header comment"
  check_file ".codex/config.toml" "Codex config.toml exists"
  check_contains ".codex/config.toml" "# --- teamrc start ---" "config.toml has teamrc start marker"
  check_contains ".codex/config.toml" "# --- teamrc end ---" "config.toml has teamrc end marker"
  check_contains ".codex/config.toml" "[agents.trc-agent]" "config.toml registers trc-agent"
  check_file "AGENTS.md" "AGENTS.md exists (Codex routing)"
  check_contains "AGENTS.md" "<!-- teamrc -->" "AGENTS.md has teamrc marker"

  subsection "Gemini"
  check_file ".gemini/agents/trc-agent.md" "Gemini agent file exists (.md)"
  check_contains ".gemini/agents/trc-agent.md" "name:" "Gemini agent has YAML frontmatter"
  check_file "GEMINI.md" "GEMINI.md exists"
  check_contains "GEMINI.md" "<!-- teamrc -->" "GEMINI.md has teamrc marker"

  subsection "Platform count in YAML"
  check_contains ".teamrc.yaml" "claude-code" ".teamrc.yaml lists claude-code"
  check_contains ".teamrc.yaml" "cursor" ".teamrc.yaml lists cursor"
  check_contains ".teamrc.yaml" "codex" ".teamrc.yaml lists codex"
  check_contains ".teamrc.yaml" "gemini" ".teamrc.yaml lists gemini"
fi

# --- 1.4: Status checks ---
subsection "Status & Doctor"
check_cmd "teamrc status exits cleanly" npx teamrc status
check_cmd "teamrc doctor exits cleanly" npx teamrc doctor

# Check --json output is valid
STATUS_JSON=$(npx teamrc status --json 2>/dev/null || echo "")
if echo "$STATUS_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  check "teamrc status --json is valid JSON" 0
else
  check "teamrc status --json is valid JSON" 1
fi

summary
