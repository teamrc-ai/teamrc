#!/bin/bash
# run-all.sh — Run all verification scripts
# Usage: bash scripts/verify/run-all.sh
#
# This runs the verification checks for the current state.
# It does NOT perform setup actions — you must run the manual test plan
# steps first, then run these scripts to verify the result.
#
# Individual sections can be run standalone:
#   bash scripts/verify/section-01-fresh-install.sh single
#   bash scripts/verify/section-01-fresh-install.sh multi
#   bash scripts/verify/section-02-collaboration.sh join
#   bash scripts/verify/section-03-platforms.sh all
#   bash scripts/verify/section-04-sync.sh
#   bash scripts/verify/section-05-rollback.sh post-delete
#   bash scripts/verify/section-06-catalog.sh
#   bash scripts/verify/section-07-cross-sync.sh
#   bash scripts/verify/section-08-errors.sh
#   bash scripts/verify/section-09-lifecycle.sh        # WARNING: destructive
#   bash scripts/verify/section-10-legacy.sh scan
#   bash scripts/verify/section-13-account.sh post-link
set -euo pipefail

DIR="$(dirname "$0")"
source "$DIR/helpers.sh"

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  teamrc Manual Test Plan — Verifier        ║${RESET}"
echo -e "${BOLD}╚════════════════════════════════════════════╝${RESET}"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SECTIONS_RUN=0
FAILED_SECTIONS=()

run_section() {
  local script="$1"
  shift
  local name
  name=$(basename "$script" .sh)

  if [ ! -f "$DIR/$script" ]; then
    echo -e "${YELLOW}⊘ Skipping $name (script not found)${RESET}"
    return
  fi

  echo -e "\n${BOLD}▶ Running $name $*${RESET}"

  # Run in subshell to capture pass/fail counts
  set +e
  output=$(bash "$DIR/$script" "$@" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  # Extract counts from output
  local p f s
  p=$(echo "$output" | grep -o "Passed:  [0-9]*" | grep -o "[0-9]*" || echo "0")
  f=$(echo "$output" | grep -o "Failed:  [0-9]*" | grep -o "[0-9]*" || echo "0")
  s=$(echo "$output" | grep -o "Skipped: [0-9]*" | grep -o "[0-9]*" || echo "0")

  TOTAL_PASS=$((TOTAL_PASS + p))
  TOTAL_FAIL=$((TOTAL_FAIL + f))
  TOTAL_SKIP=$((TOTAL_SKIP + s))
  SECTIONS_RUN=$((SECTIONS_RUN + 1))

  if [ "$f" -gt 0 ] || [ "$exit_code" -ne 0 ]; then
    FAILED_SECTIONS+=("$name $*")
  fi
}

# Determine what to verify based on current state
echo "Detecting current state..."

HAS_CONFIG=false
HAS_YAML=false
HAS_ACCOUNT=false

[ -f "$HOME/.teamrc/config.json" ] && HAS_CONFIG=true
[ -f ".teamrc.yaml" ] && HAS_YAML=true
if [ "$HAS_CONFIG" = true ] && grep -q '"account"' "$HOME/.teamrc/config.json" 2>/dev/null; then
  HAS_ACCOUNT=true
fi

echo "  Config: $HAS_CONFIG | YAML: $HAS_YAML | Account: $HAS_ACCOUNT"

# Run applicable sections
if [ "$HAS_CONFIG" = true ] && [ "$HAS_YAML" = true ]; then
  # Detect which platforms are configured
  PLATFORMS=""
  grep -q "claude-code" .teamrc.yaml 2>/dev/null && PLATFORMS="claude-code"
  grep -q "cursor" .teamrc.yaml 2>/dev/null && PLATFORMS="$PLATFORMS cursor"
  grep -q "codex" .teamrc.yaml 2>/dev/null && PLATFORMS="$PLATFORMS codex"
  grep -q "gemini" .teamrc.yaml 2>/dev/null && PLATFORMS="$PLATFORMS gemini"
  grep -q "openclaw" .teamrc.yaml 2>/dev/null && PLATFORMS="$PLATFORMS openclaw"

  PLATFORM_COUNT=$(echo "$PLATFORMS" | wc -w | tr -d ' ')

  if [ "$PLATFORM_COUNT" -gt 1 ]; then
    run_section "section-01-fresh-install.sh" "multi"
  else
    run_section "section-01-fresh-install.sh" "single"
  fi

  # Per-platform checks
  for pl in $PLATFORMS; do
    run_section "section-03-platforms.sh" "$pl"
  done

  # Sync checks (only if relay is likely running)
  RELAY_URL="${TEAMRC_RELAY:-http://localhost:4000}"
  if curl -sf "$RELAY_URL" >/dev/null 2>&1; then
    run_section "section-04-sync.sh"
  else
    echo -e "\n${YELLOW}⊘ Skipping section-04 (relay not running)${RESET}"
  fi

  # Catalog & team management (list-templates, list-agents, add-member)
  run_section "section-06-catalog.sh"

  # Multi-platform cross-sync (if 3+ platforms)
  if [ "$PLATFORM_COUNT" -ge 3 ]; then
    run_section "section-07-cross-sync.sh"
  fi

  # Account check
  if [ "$HAS_ACCOUNT" = true ]; then
    run_section "section-13-account.sh" "post-link"
  else
    run_section "section-13-account.sh" "pre-link"
  fi
fi

# Legacy scan (always useful)
run_section "section-10-legacy.sh" "scan"

# Error cases (standalone, doesn't depend on state)
run_section "section-08-errors.sh"

# Grand summary
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║            GRAND SUMMARY                   ║${RESET}"
echo -e "${BOLD}╠════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Sections run:  $SECTIONS_RUN"
echo -e "${BOLD}║${RESET}  ${GREEN}Passed:  $TOTAL_PASS${RESET}"
if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo -e "${BOLD}║${RESET}  ${RED}Failed:  $TOTAL_FAIL${RESET}"
else
  echo -e "${BOLD}║${RESET}  Failed:  0"
fi
if [ "$TOTAL_SKIP" -gt 0 ]; then
  echo -e "${BOLD}║${RESET}  ${YELLOW}Skipped: $TOTAL_SKIP${RESET}"
fi
echo -e "${BOLD}║${RESET}  Total:   $((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))"
echo -e "${BOLD}╚════════════════════════════════════════════╝${RESET}"

if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}Failed sections:${RESET}"
  for sec in "${FAILED_SECTIONS[@]}"; do
    echo -e "  ${RED}✗${RESET} $sec"
  done
  exit 1
fi

echo ""
echo -e "${GREEN}All checks passed!${RESET}"
