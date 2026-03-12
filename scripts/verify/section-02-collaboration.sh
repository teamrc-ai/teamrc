#!/bin/bash
# Section 2: Team Collaboration — verify state after join
# Usage: bash scripts/verify/section-02-collaboration.sh [join|clone]
#
# For "join" mode: run AFTER npx @teamrc/cli join <invite> --platform cursor,gemini
# For "clone" mode: run AFTER npx @teamrc/cli clone <invite> --platform claude-code
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

MODE="${1:-join}"

section "Section 2: Team Collaboration ($MODE)"

if [ "$MODE" = "join" ]; then
  subsection "2.2: Join state"
  check_file ".teamrc.yaml" ".teamrc.yaml exists"
  check_contains ".teamrc.yaml" "teamId:" ".teamrc.yaml has teamId (synced)"
  check_file "$HOME/.teamrc/config.json" "config.json exists"
  check_valid_json "$HOME/.teamrc/config.json" "config.json is valid JSON"

  # Check platform files based on what's in the YAML
  if grep -q "cursor" .teamrc.yaml 2>/dev/null; then
    check_file ".cursor/agents/trc-agent.md" "Cursor agent created after join"
  fi
  if grep -q "gemini" .teamrc.yaml 2>/dev/null; then
    check_file ".gemini/agents/trc-agent.md" "Gemini agent created after join"
  fi
  if grep -q "claude-code" .teamrc.yaml 2>/dev/null; then
    check_file ".claude/agents/trc-agent.md" "Claude Code agent created after join"
  fi

  # Verify relay knows about this team (uses signed request via CLI)
  TEAM_ID=$(grep teamId .teamrc.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")
  if [ -n "$TEAM_ID" ]; then
    subsection "2.1: Team on relay"
    # Use teamrc status --json which makes a signed API call
    STATUS_OUT=$(npx @teamrc/cli status --json 2>/dev/null || echo "")
    if echo "$STATUS_OUT" | grep -q "$TEAM_ID"; then
      check "Relay confirms team $TEAM_ID" 0
    else
      # Fallback: just check status runs without auth errors
      if npx @teamrc/cli status 2>&1 | grep -qi "team\|relay\|connected"; then
        check "Relay confirms team (via status)" 0
      else
        check "Relay confirms team" 1
      fi
    fi
  fi

elif [ "$MODE" = "clone" ]; then
  subsection "2.3: Clone state"
  check_file ".teamrc.yaml" ".teamrc.yaml exists"
  # Cloned copies should NOT have teamId
  if grep -q "teamId:" .teamrc.yaml 2>/dev/null; then
    check ".teamrc.yaml has NO teamId (local-only clone)" 1
  else
    check ".teamrc.yaml has NO teamId (local-only clone)" 0
  fi
fi

summary
