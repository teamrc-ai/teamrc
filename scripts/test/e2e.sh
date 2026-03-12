#!/bin/bash
# e2e.sh — End-to-end test runner for the manual test plan
#
# Runs across two machines:
#   Machine A (primary):   Creates team, generates invite
#   Machine B (secondary): Joins team with invite
#
# Usage:
#   Machine A:  bash scripts/test/e2e.sh --role primary   [--relay URL] [--platforms claude-code,cursor]
#   Machine B:  bash scripts/test/e2e.sh --role secondary  --invite <code> [--relay URL] [--platforms claude-code,codex,openclaw]
#
#   Single machine (both roles):
#               bash scripts/test/e2e.sh --role solo [--platforms claude-code,cursor]
#
#   Run a specific phase only:
#               bash scripts/test/e2e.sh --role primary --phase 3
#
# Environment:
#   TEAMRC_RELAY  — relay URL (default: http://localhost:4000)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_DIR="$SCRIPT_DIR/../verify"
source "$VERIFY_DIR/helpers.sh"

# ─── Parse args ───────────────────────────────────────────────
ROLE=""
INVITE=""
RELAY="${TEAMRC_RELAY:-http://localhost:4000}"
PLATFORMS=""
PHASE=""
CLI="npx teamrc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)      ROLE="$2"; shift 2 ;;
    --invite)    INVITE="$2"; shift 2 ;;
    --relay)     RELAY="$2"; shift 2 ;;
    --platforms) PLATFORMS="$2"; shift 2 ;;
    --phase)     PHASE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$ROLE" ]; then
  echo "Usage: $0 --role {primary|secondary|solo} [--invite CODE] [--relay URL] [--platforms p1,p2] [--phase N]"
  exit 1
fi

export TEAMRC_RELAY="$RELAY"

# Auto-detect platforms if not specified
if [ -z "$PLATFORMS" ]; then
  DETECTED=""
  [ -d "$HOME/.claude" ] && DETECTED="claude-code"
  [ -d ".cursor" ] || command -v cursor >/dev/null 2>&1 && DETECTED="${DETECTED:+$DETECTED,}cursor"
  [ -d ".codex" ] || command -v codex >/dev/null 2>&1 && DETECTED="${DETECTED:+$DETECTED,}codex"
  [ -d "$HOME/.openclaw" ] && DETECTED="${DETECTED:+$DETECTED,}openclaw"
  [ -d ".gemini" ] || command -v gemini >/dev/null 2>&1 && DETECTED="${DETECTED:+$DETECTED,}gemini"
  PLATFORMS="${DETECTED:-claude-code}"
fi

# Convert to array
IFS=',' read -ra PLATFORM_ARR <<< "$PLATFORMS"
PLATFORM_COUNT=${#PLATFORM_ARR[@]}

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  teamrc E2E Test — ${ROLE}                         ║${RESET}"
echo -e "${BOLD}╠════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Relay:     $RELAY"
echo -e "${BOLD}║${RESET}  Platforms: $PLATFORMS"
echo -e "${BOLD}║${RESET}  Phase:     ${PHASE:-all}"
echo -e "${BOLD}╚════════════════════════════════════════════════╝${RESET}"

should_run() {
  [ -z "$PHASE" ] || [ "$PHASE" = "$1" ]
}

# ─── State file for passing data between phases ──────────────
STATE_FILE="/tmp/teamrc-e2e-state.json"

save_state() {
  local key="$1" value="$2"
  if [ -f "$STATE_FILE" ]; then
    python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
d['$key'] = '$value'
with open('$STATE_FILE', 'w') as f: json.dump(d, f)
"
  else
    echo "{\"$key\": \"$value\"}" > "$STATE_FILE"
  fi
}

load_state() {
  local key="$1"
  if [ -f "$STATE_FILE" ]; then
    python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
print(d.get('$key', ''))
" 2>/dev/null
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 1: Clean slate + prerequisites
# ═══════════════════════════════════════════════════════════════
phase_1() {
  section "Phase 1: Clean Slate & Prerequisites"

  subsection "Prerequisites"
  check_cmd "Relay reachable" curl -sf "$RELAY"

  subsection "Clean slate"
  # Global config and legacy
  rm -rf "$HOME/.teamrc" "$HOME/.teambridge"

  # Project config
  rm -f .teamrc.yaml agent-team.yaml

  # Claude Code
  rm -f .claude/agents/trc-*.md .claude/agents/tb-*.md
  rm -f .claude/rules/trc-*.md
  rm -f teamrc-knowledge.md
  rm -rf .claude/skills/trc-*
  # Remove teamrc section from CLAUDE.md (keep the rest)
  if [ -f CLAUDE.md ]; then
    sed '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' CLAUDE.md > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
  fi

  # Cursor
  rm -f .cursor/agents/trc-*.md .cursor/agents/tb-*.md
  rm -f .cursor/rules/trc-*.mdc .cursor/rules/tb-*.mdc
  rm -rf .cursor/skills/trc-* .cursor/skills/tb-*
  # Remove teamrc section from .cursor/AGENTS.md
  if [ -f .cursor/AGENTS.md ]; then
    sed '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' .cursor/AGENTS.md > .cursor/AGENTS.md.tmp && mv .cursor/AGENTS.md.tmp .cursor/AGENTS.md
  fi

  # Codex
  rm -f .codex/agents/trc-*.toml .codex/agents/tb-*.toml
  # Remove teamrc section from .codex/config.toml
  if [ -f .codex/config.toml ]; then
    sed '/# --- teamrc start ---/,/# --- teamrc end ---/d' .codex/config.toml > .codex/config.toml.tmp && mv .codex/config.toml.tmp .codex/config.toml
  fi
  # Remove teamrc section from AGENTS.md
  if [ -f AGENTS.md ]; then
    sed '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
  fi

  # Gemini
  rm -f .gemini/agents/trc-*.md
  rm -rf .gemini/skills/trc-*
  # Remove teamrc section from GEMINI.md
  if [ -f GEMINI.md ]; then
    sed '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' GEMINI.md > GEMINI.md.tmp && mv GEMINI.md.tmp GEMINI.md
  fi

  # OpenClaw
  rm -rf "$HOME/.openclaw/workspaces/trc-"* "$HOME/.openclaw/workspaces/tb-"*

  # State file from previous runs
  rm -f "$STATE_FILE"

  check_no_dir "$HOME/.teamrc" "~/.teamrc cleaned"
  check_no_file ".teamrc.yaml" ".teamrc.yaml cleaned"
  check_no_glob ".claude/agents/trc-*.md" "Claude agents cleaned"
  check_no_glob ".cursor/agents/trc-*.md" "Cursor agents cleaned"
  check_no_glob ".codex/agents/trc-*.toml" "Codex agents cleaned"
  check_no_glob ".gemini/agents/trc-*.md" "Gemini agents cleaned"
  check "Clean slate" 0
}

# ═══════════════════════════════════════════════════════════════
# PHASE 2: Init (primary/solo) or Join (secondary)
# ═══════════════════════════════════════════════════════════════
phase_2() {
  if [ "$ROLE" = "secondary" ]; then
    phase_2_join
  else
    phase_2_init
  fi
}

phase_2_init() {
  section "Phase 2: Init (backend team template)"

  $CLI init --team backend --platform "$PLATFORMS" --relay "$RELAY" -y 2>&1 | head -20
  echo ""

  check_file ".teamrc.yaml" ".teamrc.yaml created"
  check_file "$HOME/.teamrc/config.json" "config.json created"
  check_file "$HOME/.teamrc/key" "keypair created"
  check_contains ".teamrc.yaml" "teamId:" "YAML has teamId"
  check_contains ".teamrc.yaml" "architect" "YAML has architect member"

  # Verify per-platform files (backend template has: architect, implementer, reviewer, dba)
  for pl in "${PLATFORM_ARR[@]}"; do
    case "$pl" in
      claude-code) check_file ".claude/agents/trc-architect.md" "Claude Code: architect agent" ;;
      cursor)      check_file ".cursor/agents/trc-architect.md" "Cursor: architect agent" ;;
      codex)       check_file ".codex/agents/trc-architect.toml" "Codex: architect agent (.toml)" ;;
      gemini)      check_file ".gemini/agents/trc-architect.md" "Gemini: architect agent" ;;
      openclaw)    check_dir "$HOME/.openclaw/workspaces/trc-architect" "OpenClaw: architect workspace" ;;
    esac
  done

  # Knowledge file
  check_file "teamrc-knowledge.md" "teamrc-knowledge.md created"

  # Status
  check_cmd "status exits cleanly" $CLI status
  check_cmd "doctor exits cleanly" $CLI doctor

  # Create invite for secondary machine
  subsection "Create invite"
  INVITE_OUTPUT=$($CLI invite 2>&1)
  echo "$INVITE_OUTPUT"
  INVITE_CODE=$(echo "$INVITE_OUTPUT" | grep -o "trc_inv_[A-Za-z0-9_-]*" | head -1 || echo "")

  if [ -n "$INVITE_CODE" ]; then
    check "Invite created: ${INVITE_CODE}" 0
    save_state "invite" "$INVITE_CODE"
    save_state "team_id" "$(grep teamId .teamrc.yaml | awk '{print $2}' | tr -d '\"')"

    echo ""
    echo -e "${BOLD}┌──────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│${RESET}  On the secondary machine, run:                   ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}                                                   ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}  bash scripts/test/e2e.sh \\                       ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}    --role secondary \\                             ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}    --invite ${INVITE_CODE} \\  ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}    --relay $RELAY                  ${BOLD}│${RESET}"
    echo -e "${BOLD}│${RESET}                                                   ${BOLD}│${RESET}"
    echo -e "${BOLD}└──────────────────────────────────────────────────┘${RESET}"
  else
    check "Invite created" 1
  fi
}

phase_2_join() {
  section "Phase 2: Join"

  if [ -z "$INVITE" ]; then
    echo -e "${RED}Error: --invite <code> required for secondary role${RESET}"
    exit 1
  fi

  $CLI join "$INVITE" --platform "$PLATFORMS" --relay "$RELAY" -y 2>&1 | head -20
  echo ""

  check_file ".teamrc.yaml" ".teamrc.yaml created"
  check_file "$HOME/.teamrc/config.json" "config.json created"
  check_contains ".teamrc.yaml" "teamId:" "YAML has teamId"

  # Verify per-platform files (should have agents from the team we joined)
  AGENT_COUNT=$(grep -c "name:" .teamrc.yaml 2>/dev/null | head -1 || echo "0")
  if [ "$AGENT_COUNT" -gt 0 ]; then
    for pl in "${PLATFORM_ARR[@]}"; do
      case "$pl" in
        claude-code) check_glob ".claude/agents/trc-*.md" "Claude Code agents created" ;;
        cursor)      check_glob ".cursor/agents/trc-*.md" "Cursor agents created" ;;
        codex)       check_glob ".codex/agents/trc-*.toml" "Codex agents created (.toml)" ;;
        gemini)      check_glob ".gemini/agents/trc-*.md" "Gemini agents created" ;;
        openclaw)    check_glob "$HOME/.openclaw/workspaces/trc-*" "OpenClaw workspaces created" ;;
      esac
    done
  fi

  check_cmd "status exits cleanly" $CLI status
}

# ═══════════════════════════════════════════════════════════════
# PHASE 3: Per-platform verification (detailed)
# ═══════════════════════════════════════════════════════════════
phase_3() {
  section "Phase 3: Per-Platform Verification"

  for pl in "${PLATFORM_ARR[@]}"; do
    bash "$VERIFY_DIR/section-03-platforms.sh" "$pl" 2>&1 || true
  done
}

# ═══════════════════════════════════════════════════════════════
# PHASE 4: Sync & Push
# ═══════════════════════════════════════════════════════════════
phase_4() {
  section "Phase 4: Sync & Push"

  subsection "Sync"
  check_cmd "sync exits cleanly" $CLI sync

  subsection "Push knowledge"
  echo "# Team Knowledge" > teamrc-knowledge.md
  echo "" >> teamrc-knowledge.md
  echo "## Test Entry" >> teamrc-knowledge.md
  echo "E2E test from $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> teamrc-knowledge.md

  PUSH_OUT=$($CLI push 2>&1 || true)
  if echo "$PUSH_OUT" | grep -qi "push\|success\|knowledge"; then
    check "push completes" 0
  else
    check "push completes (output: $PUSH_OUT)" 1
  fi

  subsection "Diff"
  check_cmd "diff exits cleanly" $CLI diff

  subsection "Pull (sync after push)"
  check_cmd "sync after push" $CLI sync
}

# ═══════════════════════════════════════════════════════════════
# PHASE 5: Cross-machine sync (run on BOTH machines)
# ═══════════════════════════════════════════════════════════════
phase_5() {
  section "Phase 5: Cross-Machine Sync"

  subsection "Push unique knowledge from this machine"
  echo "## $(hostname) Finding" >> teamrc-knowledge.md
  echo "Cross-machine test at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> teamrc-knowledge.md
  $CLI push 2>&1 | head -5

  subsection "Sync to pull other machine's changes"
  $CLI sync 2>&1 | head -10

  # Verify knowledge file has content
  check_file "teamrc-knowledge.md" "teamrc-knowledge.md exists"
  if [ -s "teamrc-knowledge.md" ]; then
    check "teamrc-knowledge.md has content" 0
  else
    check "teamrc-knowledge.md has content" 1
  fi

  subsection "Status confirms relay connection"
  STATUS=$($CLI status --json 2>/dev/null || echo "{}")
  if echo "$STATUS" | grep -q '"connected": true'; then
    check "Relay connected" 0
  else
    check "Relay connected" 1
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 6: Error cases
# ═══════════════════════════════════════════════════════════════
phase_6() {
  section "Phase 6: Error Cases"
  bash "$VERIFY_DIR/section-08-errors.sh" 2>&1 || true
}

# ═══════════════════════════════════════════════════════════════
# PHASE 7: Rollback — delete and re-join
# ═══════════════════════════════════════════════════════════════
phase_7() {
  section "Phase 7: Rollback"

  # Save current invite for re-join
  local saved_invite
  saved_invite=$(load_state "invite")

  subsection "Delete"
  $CLI delete -y 2>&1 | head -10
  echo ""

  check_no_file ".teamrc.yaml" ".teamrc.yaml removed"

  for pl in "${PLATFORM_ARR[@]}"; do
    case "$pl" in
      claude-code) check_no_glob ".claude/agents/trc-*.md" "Claude agents removed" ;;
      cursor)      check_no_glob ".cursor/agents/trc-*.md" "Cursor agents removed" ;;
      codex)       check_no_glob ".codex/agents/trc-*.toml" "Codex agents removed" ;;
      gemini)      check_no_glob ".gemini/agents/trc-*.md" "Gemini agents removed" ;;
      openclaw)    check_no_glob "$HOME/.openclaw/workspaces/trc-*" "OpenClaw workspaces removed" ;;
    esac
  done

  subsection "Re-init"
  $CLI init --team backend --platform "$PLATFORMS" --relay "$RELAY" -y 2>&1 | head -15
  echo ""

  check_file ".teamrc.yaml" ".teamrc.yaml recreated"
  check_cmd "doctor passes after re-init" $CLI doctor

  # Create new invite (old one tied to old team)
  INVITE_OUTPUT=$($CLI invite 2>&1)
  NEW_INVITE=$(echo "$INVITE_OUTPUT" | grep -o "trc_inv_[A-Za-z0-9_-]*" | head -1 || echo "")
  if [ -n "$NEW_INVITE" ]; then
    save_state "invite" "$NEW_INVITE"
    check "New invite created after re-init" 0
  fi

  subsection "Delete again"
  $CLI delete -y 2>&1 | head -5

  subsection "Re-join with new invite"
  if [ -n "$NEW_INVITE" ]; then
    $CLI join "$NEW_INVITE" --platform "$PLATFORMS" --relay "$RELAY" -y 2>&1 | head -10
    echo ""
    check_file ".teamrc.yaml" ".teamrc.yaml after re-join"
    check_cmd "status after re-join" $CLI status
  else
    skip "Re-join" "no invite available"
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 8: Legacy cleanup scan
# ═══════════════════════════════════════════════════════════════
phase_8() {
  section "Phase 8: Legacy TeamBridge Scan"
  bash "$VERIFY_DIR/section-10-legacy.sh" scan 2>&1 || true
}

# ═══════════════════════════════════════════════════════════════
# PHASE 9: Corrupt/missing config recovery
# ═══════════════════════════════════════════════════════════════
phase_9() {
  section "Phase 9: Recovery"

  subsection "Corrupt config"
  # Save good config
  cp "$HOME/.teamrc/config.json" /tmp/teamrc-config-backup.json 2>/dev/null || true

  if [ -d "$HOME/.teamrc" ]; then
    echo "{broken" > "$HOME/.teamrc/config.json"
    STATUS_OUT=$($CLI status 2>&1 || true)
    if echo "$STATUS_OUT" | grep -qi "not initialized\|error\|no team"; then
      check "Corrupt config handled gracefully" 0
    else
      check "Corrupt config handled gracefully" 1
    fi

    # Restore
    cp /tmp/teamrc-config-backup.json "$HOME/.teamrc/config.json" 2>/dev/null || true
  else
    skip "Corrupt config" "~/.teamrc doesn't exist"
  fi

  subsection "Missing keypair"
  if [ -f "$HOME/.teamrc/key" ]; then
    cp "$HOME/.teamrc/key" /tmp/teamrc-key-backup 2>/dev/null
    rm -f "$HOME/.teamrc/key"
    $CLI init --platform "${PLATFORM_ARR[0]}" --relay "$RELAY" -y 2>&1 | head -5
    check_file "$HOME/.teamrc/key" "Keypair regenerated"
    # Restore (new key is fine, but restore to keep same identity)
    cp /tmp/teamrc-key-backup "$HOME/.teamrc/key" 2>/dev/null || true
  else
    skip "Missing keypair" "~/.teamrc/key doesn't exist"
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 10: Final status
# ═══════════════════════════════════════════════════════════════
phase_10() {
  section "Phase 10: Final Verification"

  check_cmd "status" $CLI status
  check_cmd "doctor" $CLI doctor

  STATUS=$($CLI status --json 2>/dev/null || echo "{}")
  if echo "$STATUS" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    check "status --json valid" 0
  else
    check "status --json valid" 1
  fi

  if echo "$STATUS" | grep -q '"connected": true'; then
    check "Relay connected (final)" 0
  else
    check "Relay connected (final)" 1
  fi

  TEAM_ID=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('teamId',''))" 2>/dev/null || echo "")
  if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "None" ] && [ "$TEAM_ID" != "null" ]; then
    check "Team ID present: ${TEAM_ID:0:12}..." 0
  else
    check "Team ID present" 1
  fi
}

# ═══════════════════════════════════════════════════════════════
# Run phases
# ═══════════════════════════════════════════════════════════════

if [ "$ROLE" = "solo" ]; then
  # Solo: run everything on one machine
  should_run 1 && phase_1
  should_run 2 && phase_2
  should_run 3 && phase_3
  should_run 4 && phase_4
  should_run 6 && phase_6
  should_run 7 && phase_7
  should_run 8 && phase_8
  should_run 9 && phase_9
  should_run 10 && phase_10

elif [ "$ROLE" = "primary" ]; then
  # Primary: init, create invite, test, wait for secondary
  should_run 1 && phase_1
  should_run 2 && phase_2
  should_run 3 && phase_3
  should_run 4 && phase_4

  if should_run 5; then
    echo ""
    echo -e "${YELLOW}═══ Pause: Run phases 1-4 on secondary machine, then continue ═══${RESET}"
    echo -e "${YELLOW}    Press Enter when secondary machine has joined and pushed...${RESET}"
    read -r
    phase_5
  fi

  should_run 6 && phase_6
  should_run 7 && phase_7
  should_run 8 && phase_8
  should_run 9 && phase_9
  should_run 10 && phase_10

elif [ "$ROLE" = "secondary" ]; then
  # Secondary: join, test, sync
  should_run 1 && phase_1
  should_run 2 && phase_2
  should_run 3 && phase_3
  should_run 4 && phase_4
  should_run 5 && phase_5
  should_run 6 && phase_6
  should_run 8 && phase_8
  should_run 10 && phase_10
fi

# ─── Grand summary ───────────────────────────────────────────
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║            E2E TEST COMPLETE                   ║${RESET}"
echo -e "${BOLD}╠════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Role:      $ROLE"
echo -e "${BOLD}║${RESET}  Platforms: $PLATFORMS"
echo -e "${BOLD}║${RESET}  Relay:     $RELAY"
summary
