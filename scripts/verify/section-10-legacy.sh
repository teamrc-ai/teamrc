#!/bin/bash
# Section 10: Legacy TeamBridge Cleanup
# Usage: bash scripts/verify/section-10-legacy.sh [scan|post-uninstall|post-init]
#   scan           — identify all TeamBridge artifacts (10.1)
#   post-uninstall — verify cleanup after uninstall.sh (10.2/10.5)
#   post-init      — verify fresh init uses trc- prefix (10.6)
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

MODE="${1:-scan}"

section "Section 10: Legacy TeamBridge Cleanup ($MODE)"

case "$MODE" in
  scan)
    subsection "10.1: Scanning for TeamBridge artifacts"

    # Config directory
    if [ -d "$HOME/.teambridge" ]; then
      check "~/.teambridge/ does NOT exist" 1
    else
      check "~/.teambridge/ does NOT exist" 0
    fi

    # Claude Code agents
    check_no_glob ".claude/agents/tb-*.md" "No tb-*.md in .claude/agents/"
    check_no_glob "$HOME/.claude/agents/tb-*.md" "No tb-*.md in ~/.claude/agents/"

    # Cursor agents and rules
    check_no_glob ".cursor/agents/tb-*.md" "No tb-*.md in .cursor/agents/"
    check_no_glob ".cursor/rules/tb-*.mdc" "No tb-*.mdc in .cursor/rules/"

    # Codex agents
    check_no_glob ".codex/agents/tb-*.toml" "No tb-*.toml in .codex/agents/"

    # OpenClaw workspaces
    check_no_glob "$HOME/.openclaw/workspaces/tb-*" "No tb-* OpenClaw workspaces"

    # Content references
    check_not_contains "openclaw.json" "tb-" "openclaw.json has no tb- references"
    check_not_contains "CLAUDE.md" "TeamBridge" "CLAUDE.md has no TeamBridge references"
    check_not_contains "CLAUDE.md" "tb-" "CLAUDE.md has no tb- references"
    check_not_contains "$HOME/.claude/settings.json" "teambridge" "~/.claude/settings.json has no teambridge"
    check_not_contains "AGENTS.md" "TeamBridge" "AGENTS.md has no TeamBridge references"
    check_not_contains "AGENTS.md" "tb-" "AGENTS.md has no tb- references"
    check_not_contains "GEMINI.md" "TeamBridge" "GEMINI.md has no TeamBridge references"
    check_not_contains "GEMINI.md" "tb-" "GEMINI.md has no tb- references"
    check_not_contains ".codex/config.toml" "tb-" ".codex/config.toml has no tb- references"

    # Broad search
    echo ""
    echo "  Broad search for remaining references:"
    FOUND=$(grep -rl "TeamBridge\|teambridge\|tb-" \
      .claude/ .cursor/ .codex/ .gemini/ \
      CLAUDE.md AGENTS.md GEMINI.md \
      openclaw.json .codex/config.toml \
      "$HOME/.claude/settings.json" \
      2>/dev/null || true)
    if [ -z "$FOUND" ]; then
      check "Zero remaining TeamBridge/tb- references" 0
    else
      check "Zero remaining TeamBridge/tb- references" 1
      echo "    Found in: $FOUND"
    fi
    ;;

  post-uninstall)
    subsection "10.2/10.5: After uninstall.sh"
    check_no_dir "$HOME/.teambridge" "~/.teambridge/ removed"
    check_no_dir "$HOME/.teamrc" "~/.teamrc/ removed"
    check_no_file ".teamrc.yaml" ".teamrc.yaml removed"
    check_no_glob ".claude/agents/tb-*.md" "No tb-*.md Claude agents"
    check_no_glob ".claude/agents/trc-*.md" "No trc-*.md Claude agents"
    check_no_glob ".cursor/agents/tb-*.md" "No tb-*.md Cursor agents"
    check_no_glob ".cursor/agents/trc-*.md" "No trc-*.md Cursor agents"
    check_no_glob ".cursor/rules/tb-*.mdc" "No tb-*.mdc Cursor rules"
    check_no_glob ".codex/agents/tb-*.toml" "No tb-*.toml Codex agents"
    check_no_glob ".codex/agents/trc-*.toml" "No trc-*.toml Codex agents"
    check_no_glob "$HOME/.openclaw/workspaces/tb-*" "No tb-* OpenClaw workspaces"
    check_no_glob "$HOME/.openclaw/workspaces/trc-*" "No trc-* OpenClaw workspaces"

    # Check settings.json was cleaned
    check_not_contains "$HOME/.claude/settings.json" "teambridge" "Settings cleaned of teambridge"
    check_not_contains "$HOME/.claude/settings.json" "AGENT_TEAMS" "Settings cleaned of AGENT_TEAMS"
    ;;

  post-init)
    subsection "10.6: Fresh init uses trc- prefix"
    check_file ".teamrc.yaml" ".teamrc.yaml created (not agent-team.yaml)"
    check_no_file "agent-team.yaml" "No legacy agent-team.yaml"
    check_dir "$HOME/.teamrc" "~/.teamrc/ created"
    check_no_dir "$HOME/.teambridge" "~/.teambridge/ NOT created"

    # All agent files use trc- prefix
    if ls .claude/agents/trc-*.md 1>/dev/null 2>&1; then
      check "Claude agents use trc- prefix" 0
    else
      skip "Claude agents prefix check" "no Claude agents found"
    fi

    # No tb- prefix files
    check_no_glob ".claude/agents/tb-*.md" "No tb- prefixed Claude agents"
    check_no_glob ".cursor/agents/tb-*.md" "No tb- prefixed Cursor agents"
    check_no_glob ".codex/agents/tb-*.toml" "No tb- prefixed Codex agents"

    check_cmd "doctor passes" npx @teamrc/cli doctor
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 {scan|post-uninstall|post-init}"
    exit 1
    ;;
esac

summary
