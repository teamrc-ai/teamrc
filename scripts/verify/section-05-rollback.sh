#!/bin/bash
# Section 5: Rollback Scenarios — verify state after various rollbacks
# Usage: bash scripts/verify/section-05-rollback.sh <scenario>
#   post-delete    — verify after: npx @teamrc/cli delete (--scope all)
#   post-reinit    — verify after: delete then init
#   post-uninstall — verify after: bash scripts/uninstall.sh
#   corrupt-config — test corrupt config recovery
#   missing-keypair — test missing keypair recovery
#   scope-switch   — verify project vs global mode
#   scope-project  — verify after: npx @teamrc/cli delete --scope project
#   scope-global   — verify after: npx @teamrc/cli delete --scope global
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

SCENARIO="${1:-post-delete}"

section "Section 5: Rollback Scenarios ($SCENARIO)"

case "$SCENARIO" in
  post-delete)
    subsection "5.1: After teamrc delete (--scope all)"
    check_no_file ".teamrc.yaml" ".teamrc.yaml removed"
    check_no_dir ".teamrc" ".teamrc/ state dir removed"
    check_no_dir "$HOME/.teamrc" "~/.teamrc/ removed"
    check_no_glob ".claude/agents/trc-*.md" "No Claude Code trc-* agents"
    check_no_glob ".cursor/agents/trc-*.md" "No Cursor trc-* agents"
    check_no_glob ".codex/agents/trc-*.toml" "No Codex trc-* agents"
    check_no_glob ".gemini/agents/trc-*.md" "No Gemini trc-* agents"
    check_no_glob "$HOME/.openclaw/agents/trc-*.md" "No OpenClaw trc-* agents"
    ;;

  post-reinit)
    subsection "5.1: After delete + re-init"
    check_file ".teamrc.yaml" ".teamrc.yaml recreated"
    check_dir ".teamrc" ".teamrc/ state dir recreated"
    check_dir "$HOME/.teamrc" "~/.teamrc/ recreated"
    check_file "$HOME/.teamrc/config.json" "config.json recreated"
    check_valid_json "$HOME/.teamrc/config.json" "config.json is valid JSON"
    check_cmd "teamrc doctor passes" npx @teamrc/cli doctor
    ;;

  post-uninstall)
    subsection "5.3: After uninstall.sh"
    check_no_dir "$HOME/.teamrc" "~/.teamrc/ removed"
    check_no_dir "$HOME/.teambridge" "~/.teambridge/ removed"
    check_no_file ".teamrc.yaml" ".teamrc.yaml removed"
    check_no_glob ".claude/agents/trc-*.md" "No trc-* Claude agents"
    check_no_glob ".claude/agents/tb-*.md" "No tb-* Claude agents"
    check_no_glob ".cursor/agents/trc-*.md" "No trc-* Cursor agents"
    check_no_glob ".cursor/agents/tb-*.md" "No tb-* Cursor agents"
    check_no_glob ".codex/agents/trc-*.toml" "No trc-* Codex agents"
    check_no_glob ".codex/agents/tb-*.toml" "No tb-* Codex agents"
    check_no_glob "$HOME/.openclaw/agents/trc-*.md" "No trc-* OpenClaw agents"
    check_no_glob "$HOME/.openclaw/agents/tb-*.md" "No tb-* OpenClaw agents"
    ;;

  corrupt-config)
    subsection "5.4: Corrupt config recovery"
    # First corrupt it
    if [ -d "$HOME/.teamrc" ]; then
      echo "{invalid json" > "$HOME/.teamrc/config.json"
      echo "  (Corrupted config.json for testing)"
      # Status should handle it gracefully (not crash)
      if npx @teamrc/cli status 2>&1 | grep -qi "not initialized\|error\|no team"; then
        check "Status handles corrupt config gracefully" 0
      else
        check "Status handles corrupt config gracefully" 1
      fi
    else
      skip "Corrupt config test" "~/.teamrc does not exist, run init first"
    fi
    ;;

  missing-keypair)
    subsection "5.5: Missing keypair recovery"
    if [ -f "$HOME/.teamrc/key" ]; then
      rm -f "$HOME/.teamrc/key"
      echo "  (Deleted keypair file for testing)"
      check_cmd "Init recovers from missing keypair" npx @teamrc/cli init --platform claude-code
      if [ -f "$HOME/.teamrc/key" ]; then
        check "New keypair generated" 0
      else
        check "New keypair generated" 1
      fi
    else
      skip "Missing keypair test" "~/.teamrc/key does not exist"
    fi
    ;;

  scope-switch)
    subsection "5.6: Project vs Global scope"
    # Check current state
    if [ -f ".teamrc.yaml" ]; then
      check "Project mode: .teamrc.yaml exists" 0
      check_glob ".claude/agents/trc-*.md" "Project mode: .claude/agents/ has agents"
    elif grep -q "globalTeam" "$HOME/.teamrc/config.json" 2>/dev/null; then
      check "Global mode: globalTeam in config.json" 0
      check_no_file ".teamrc.yaml" "Global mode: no .teamrc.yaml"
      check_glob "$HOME/.claude/agents/trc-*.md" "Global mode: ~/.claude/agents/ has agents"
    else
      check "Either project or global mode detected" 1
    fi
    ;;

  scope-project)
    subsection "5.7: After teamrc delete --scope project"
    check_no_file ".teamrc.yaml" ".teamrc.yaml removed"
    check_no_dir ".teamrc" ".teamrc/ state dir removed"
    check_no_glob ".claude/agents/trc-*.md" "No Claude Code trc-* agents"
    check_no_glob ".cursor/agents/trc-*.md" "No Cursor trc-* agents"
    check_no_glob ".codex/agents/trc-*.toml" "No Codex trc-* agents"
    check_no_glob ".gemini/agents/trc-*.md" "No Gemini trc-* agents"
    check_no_glob "$HOME/.openclaw/agents/trc-*.md" "No OpenClaw trc-* agents"
    # Global config should still exist
    check_dir "$HOME/.teamrc" "~/.teamrc/ still exists"
    check_file "$HOME/.teamrc/config.json" "config.json still exists"
    check_file "$HOME/.teamrc/key" "keypair still exists"
    ;;

  scope-global)
    subsection "5.8: After teamrc delete --scope global"
    # Global team YAML removed, but global config dir + keypair preserved
    check_no_file "$HOME/.teamrc/team.yaml" "~/.teamrc/team.yaml removed"
    check_dir "$HOME/.teamrc" "~/.teamrc/ still exists"
    check_file "$HOME/.teamrc/config.json" "config.json still exists"
    # Project files should still exist
    check_file ".teamrc.yaml" ".teamrc.yaml still exists"
    check_dir ".teamrc" ".teamrc/ state dir still exists"
    ;;

  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Usage: $0 {post-delete|post-reinit|post-uninstall|corrupt-config|missing-keypair|scope-switch|scope-project|scope-global}"
    exit 1
    ;;
esac

summary
