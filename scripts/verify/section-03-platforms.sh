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

verify_claude_code() {
  subsection "3.1: Claude Code"
  check_file ".claude/agents/trc-agent.md" "Agent file: .claude/agents/trc-agent.md"
  check_contains ".claude/agents/trc-agent.md" "name:" "Agent has YAML frontmatter (name:)"
  check_contains ".claude/agents/trc-agent.md" "description:" "Agent has YAML frontmatter (description:)"

  check_file "CLAUDE.md" "CLAUDE.md exists"
  check_contains "CLAUDE.md" "<!-- teamrc -->" "CLAUDE.md has <!-- teamrc --> marker"
  check_contains "CLAUDE.md" "<!-- /teamrc -->" "CLAUDE.md has <!-- /teamrc --> marker"
  check_contains "CLAUDE.md" "team-knowledge.md" "CLAUDE.md references team-knowledge.md"
}

verify_cursor() {
  subsection "3.2: Cursor"
  check_file ".cursor/agents/trc-agent.md" "Agent file: .cursor/agents/trc-agent.md"
  check_contains ".cursor/agents/trc-agent.md" "name:" "Agent has YAML frontmatter (name:)"
  check_contains ".cursor/agents/trc-agent.md" "description:" "Agent has YAML frontmatter (description:)"

  if [ -f ".cursor/AGENTS.md" ]; then
    check_contains ".cursor/AGENTS.md" "<!-- teamrc -->" "AGENTS.md has <!-- teamrc --> marker"
    check_contains ".cursor/AGENTS.md" "<!-- /teamrc -->" "AGENTS.md has <!-- /teamrc --> marker"
  else
    skip "Cursor AGENTS.md" "not created by adapter"
  fi
}

verify_codex() {
  subsection "3.3: Codex (TOML format)"
  check_file ".codex/agents/trc-agent.toml" "Agent file: .codex/agents/trc-agent.toml (.toml, NOT .md)"
  check_contains ".codex/agents/trc-agent.toml" 'developer_instructions = """' "Agent has developer_instructions block"
  check_contains ".codex/agents/trc-agent.toml" '# teamrc agent:' "Agent has header comment"

  check_file ".codex/config.toml" "Config: .codex/config.toml"
  check_contains ".codex/config.toml" '# --- teamrc start ---' "config.toml has start marker"
  check_contains ".codex/config.toml" '# --- teamrc end ---' "config.toml has end marker"
  check_contains ".codex/config.toml" '[agents.trc-agent]' "config.toml has [agents.trc-agent] section"
  check_contains ".codex/config.toml" 'config_file' "config.toml has config_file reference"

  check_file "AGENTS.md" "Routing file: AGENTS.md"
  check_contains "AGENTS.md" "<!-- teamrc -->" "AGENTS.md has <!-- teamrc --> marker"
  check_contains "AGENTS.md" "<!-- /teamrc -->" "AGENTS.md has <!-- /teamrc --> marker"

  # Negative: no .md agent file
  check_no_glob ".codex/agents/trc-*.md" "No .md agent files in .codex/agents/ (Codex uses .toml)"
}

verify_gemini() {
  subsection "3.4: Gemini"
  check_file ".gemini/agents/trc-agent.md" "Agent file: .gemini/agents/trc-agent.md"
  check_contains ".gemini/agents/trc-agent.md" "name:" "Agent has YAML frontmatter (name:)"
  check_contains ".gemini/agents/trc-agent.md" "description:" "Agent has YAML frontmatter (description:)"

  check_file "GEMINI.md" "Routing file: GEMINI.md"
  check_contains "GEMINI.md" "<!-- teamrc -->" "GEMINI.md has <!-- teamrc --> marker"
  check_contains "GEMINI.md" "<!-- /teamrc -->" "GEMINI.md has <!-- /teamrc --> marker"
}

verify_openclaw() {
  subsection "3.5: OpenClaw"
  check_dir "$HOME/.openclaw/workspaces/trc-agent" "Workspace: ~/.openclaw/workspaces/trc-agent/"
  check_file "$HOME/.openclaw/workspaces/trc-agent/SOUL.md" "SOUL.md exists in workspace"
  check_file "$HOME/.openclaw/workspaces/trc-agent/AGENTS.md" "AGENTS.md exists in workspace"
  check_contains "$HOME/.openclaw/workspaces/trc-agent/AGENTS.md" "teamrc" "AGENTS.md has teamrc routing"

  if [ -f "openclaw.json" ]; then
    check_contains "openclaw.json" "trc-agent" "openclaw.json registers trc-agent"
  else
    skip "openclaw.json registration" "file not found"
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
