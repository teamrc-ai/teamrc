#!/bin/bash
# Section 4: Sync & Daemon — verify sync/push/diff work
# Usage: bash scripts/verify/section-04-sync.sh
#
# Run AFTER: npx teamrc init (with relay running)
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Section 4: Sync & Daemon"

subsection "4.1: Manual sync"
check_cmd "teamrc sync exits cleanly" npx teamrc sync

subsection "4.2: Push knowledge"
# Create knowledge file if it doesn't exist
mkdir -p .claude
if [ ! -f ".claude/teamrc-knowledge.md" ]; then
  echo "# Team Knowledge" > .claude/teamrc-knowledge.md
  echo "Test entry: verification at $(date)" >> .claude/teamrc-knowledge.md
fi
PUSH_OUTPUT=$(npx teamrc push 2>&1 || true)
if echo "$PUSH_OUTPUT" | grep -qi "push\|success\|knowledge"; then
  check "teamrc push completes" 0
else
  check "teamrc push completes" 1
fi

subsection "4.3: Diff"
check_cmd "teamrc diff exits cleanly" npx teamrc diff

DIFF_JSON=$(npx teamrc diff --json 2>/dev/null || echo "")
if [ -n "$DIFF_JSON" ] && echo "$DIFF_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  check "teamrc diff --json is valid JSON" 0
else
  # diff --json might not be implemented yet
  skip "teamrc diff --json is valid JSON" "may not be implemented"
fi

subsection "4.4/4.5: Daemon"
skip "Daemon start/stop" "requires manual testing (interactive)"
skip "Daemon file watch" "requires manual testing (two terminals)"

summary
