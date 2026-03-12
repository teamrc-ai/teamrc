#!/bin/bash
# Section 9: Full Reset Sequence — runs and verifies a complete lifecycle
# Usage: bash scripts/verify/section-09-lifecycle.sh
#
# WARNING: This script DELETES and re-creates teamrc state.
# It requires the relay to be running.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

CLI="npx @teamrc/cli"

section "Section 9: Full Reset Sequence"

# Prereqs
subsection "Prerequisites"
check_cmd "PostgreSQL running" pg_isready
check_relay

subsection "Step 1: Clean slate"
rm -rf "$HOME/.teamrc"
bash scripts/uninstall.sh 2>/dev/null || true
check_no_dir "$HOME/.teamrc" "~/.teamrc removed"

subsection "Step 2: Init"
OUTPUT=$($CLI init --platform claude-code,cursor -y 2>&1 || true)
check_file ".teamrc.yaml" ".teamrc.yaml created"
check_file "$HOME/.teamrc/config.json" "config created"
check_file ".claude/agents/trc-agent.md" "Claude Code agent created"
check_file ".cursor/agents/trc-agent.md" "Cursor agent created"
check_dir ".teamrc" ".teamrc/ state dir created"

# Doctor
$CLI doctor >/dev/null 2>&1
check "doctor passes after init" $?

subsection "Step 3: Create invite"
INVITE=$($CLI invite 2>&1 | grep -o "trc_inv_[A-Za-z0-9_-]*" | head -1 || echo "")
if [ -n "$INVITE" ]; then
  check "Invite code extracted: ${INVITE:0:20}..." 0
else
  check "Invite code extracted" 1
  echo "  Cannot continue without invite code."
  summary
  exit 1
fi

subsection "Step 4: Delete everything (--scope all)"
$CLI delete --scope all -y 2>/dev/null || true
check_no_file ".teamrc.yaml" ".teamrc.yaml deleted"
check_no_dir ".teamrc" ".teamrc/ state dir removed"
check_no_dir "$HOME/.teamrc" "~/.teamrc deleted"
check_no_glob ".claude/agents/trc-*.md" "Claude agents removed"
check_no_glob ".cursor/agents/trc-*.md" "Cursor agents removed"

subsection "Step 5: Re-join with saved invite"
OUTPUT=$($CLI join "$INVITE" --platform claude-code,cursor -y 2>&1 || true)
if echo "$OUTPUT" | grep -qi "joined\|applied"; then
  check "Re-join succeeded" 0
else
  check "Re-join succeeded" 1
fi
check_file ".teamrc.yaml" ".teamrc.yaml recreated"
check_file ".claude/agents/trc-agent.md" "Claude agent recreated"

subsection "Step 6: Verify"
check_cmd "status exits cleanly" $CLI status
check_cmd "diff exits cleanly" $CLI diff

subsection "Step 7: Sync"
SYNC_OUTPUT=$($CLI sync 2>&1 || true)
if echo "$SYNC_OUTPUT" | grep -qi "sync\|up to date\|applied\|change"; then
  check "Sync completes" 0
else
  check "Sync completes" 1
fi
check_file ".teamrc/state.json" "state.json exists after sync"

subsection "Step 8: Export"
check_cmd "export exits cleanly" $CLI export
check_file ".teamrc.yaml" ".teamrc.yaml exists after export"

subsection "Step 9: Delete again"
$CLI delete --scope all -y 2>/dev/null || true
check_no_file ".teamrc.yaml" ".teamrc.yaml deleted (round 2)"
check_no_dir ".teamrc" ".teamrc/ state dir removed (round 2)"

subsection "Step 10: Re-init fresh"
$CLI init --platform claude-code -y >/dev/null 2>&1 || true
check_file ".teamrc.yaml" ".teamrc.yaml created (fresh)"
check_file "$HOME/.teamrc/config.json" "config created (fresh)"

subsection "Step 11: Final verify"
check_cmd "doctor passes (final)" $CLI doctor

STATUS_JSON=$($CLI status --json 2>/dev/null || echo "")
if echo "$STATUS_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  check "status --json is valid JSON (final)" 0
else
  check "status --json is valid JSON (final)" 1
fi

summary
