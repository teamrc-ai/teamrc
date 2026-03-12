#!/bin/bash
# Section 3: Per-Platform Verification
# Usage: bash scripts/verify/section-03-platforms.sh <platform>
#   e.g.: bash scripts/verify/section-03-platforms.sh claude-code
#         bash scripts/verify/section-03-platforms.sh all
#
# Run AFTER: npx teamrc init --platform <platform>
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PLATFORM="${1:-all}"

# Find the first trc-* agent file for content checks
first_agent() {
  local dir="$1" ext="$2"
  ls "$dir"/trc-*"$ext" 2>/dev/null | head -1 || echo ""
}

verify_claude_code() {
  subsection "3.1: Claude Code"
  check_glob ".claude/agents/trc-*.md" "Agent files exist"
  AGENT=$(first_agent ".claude/agents" ".md")
  if [ -n "$AGENT" ]; then
    check_contains "$AGENT" "name:" "Agent has YAML frontmatter (name:)"
    check_contains "$AGENT" "description:" "Agent has YAML frontmatter (description:)"
  fi

  check_file "CLAUDE.md" "CLAUDE.md exists"
  check_contains "CLAUDE.md" "<!-- teamrc -->" "CLAUDE.md has <!-- teamrc --> marker"
  check_contains "CLAUDE.md" "<!-- /teamrc -->" "CLAUDE.md has <!-- /teamrc --> marker"
  check_contains "CLAUDE.md" "teamrc-knowledge.md" "CLAUDE.md references teamrc-knowledge.md"
}

verify_cursor() {
  subsection "3.2: Cursor"
  check_glob ".cursor/agents/trc-*.md" "Agent files exist"
  AGENT=$(first_agent ".cursor/agents" ".md")
  if [ -n "$AGENT" ]; then
    check_contains "$AGENT" "name:" "Agent has YAML frontmatter (name:)"
    check_contains "$AGENT" "description:" "Agent has YAML frontmatter (description:)"
  fi

  if [ -f ".cursor/AGENTS.md" ]; then
    check_contains ".cursor/AGENTS.md" "<!-- teamrc -->" "AGENTS.md has <!-- teamrc --> marker"
    check_contains ".cursor/AGENTS.md" "<!-- /teamrc -->" "AGENTS.md has <!-- /teamrc --> marker"
  else
    skip "Cursor AGENTS.md" "not created by adapter"
  fi
}

verify_codex() {
  subsection "3.3: Codex (TOML format)"
  check_glob ".codex/agents/trc-*.toml" "Agent files exist (.toml)"
  AGENT=$(first_agent ".codex/agents" ".toml")
  if [ -n "$AGENT" ]; then
    check_contains "$AGENT" 'developer_instructions = """' "Agent has developer_instructions block"
    check_contains "$AGENT" '# teamrc agent:' "Agent has header comment"
  fi

  check_file ".codex/config.toml" "Config: .codex/config.toml"
  check_contains ".codex/config.toml" '# --- teamrc start ---' "config.toml has start marker"
  check_contains ".codex/config.toml" '# --- teamrc end ---' "config.toml has end marker"
  check_contains ".codex/config.toml" '[agents.trc-' "config.toml has [agents.trc-*] section"
  check_contains ".codex/config.toml" 'config_file' "config.toml has config_file reference"

  check_file "AGENTS.md" "Routing file: AGENTS.md"
  check_contains "AGENTS.md" "<!-- teamrc -->" "AGENTS.md has <!-- teamrc --> marker"
  check_contains "AGENTS.md" "<!-- /teamrc -->" "AGENTS.md has <!-- /teamrc --> marker"

  # Negative: no .md agent file
  check_no_glob ".codex/agents/trc-*.md" "No .md agent files in .codex/agents/ (Codex uses .toml)"
}

verify_gemini() {
  subsection "3.4: Gemini"
  check_glob ".gemini/agents/trc-*.md" "Agent files exist"
  AGENT=$(first_agent ".gemini/agents" ".md")
  if [ -n "$AGENT" ]; then
    check_contains "$AGENT" "name:" "Agent has YAML frontmatter (name:)"
    check_contains "$AGENT" "description:" "Agent has YAML frontmatter (description:)"
  fi

  check_file "GEMINI.md" "Routing file: GEMINI.md"
  check_contains "GEMINI.md" "<!-- teamrc -->" "GEMINI.md has <!-- teamrc --> marker"
  check_contains "GEMINI.md" "<!-- /teamrc -->" "GEMINI.md has <!-- /teamrc --> marker"
}

verify_openclaw() {
  subsection "3.5: OpenClaw"
  check_glob "$HOME/.openclaw/workspaces/trc-*" "Workspaces exist"
  WORKSPACE=$(ls -d "$HOME/.openclaw/workspaces/trc-"* 2>/dev/null | head -1 || echo "")
  if [ -n "$WORKSPACE" ]; then
    check_file "$WORKSPACE/AGENTS.md" "AGENTS.md exists in workspace"
    check_contains "$WORKSPACE/AGENTS.md" "teamrc" "AGENTS.md has teamrc routing"
  fi
}

section "Section 3: Per-Platform Verification"

case "$PLATFORM" in
  claude-code) verify_claude_code ;;
  cursor) verify_cursor ;;
  codex) verify_codex ;;
  gemini) verify_gemini ;;
  openclaw) verify_openclaw ;;
  all)
    verify_claude_code
    verify_cursor
    verify_codex
    verify_gemini
    verify_openclaw
    ;;
  *)
    echo "Unknown platform: $PLATFORM"
    echo "Usage: $0 {claude-code|cursor|codex|gemini|openclaw|all}"
    exit 1
    ;;
esac

summary
