#!/bin/bash
# helpers.sh — Shared verification functions for the manual test plan
# Source this file from section scripts: source "$(dirname "$0")/helpers.sh"

PASS=0
FAIL=0
SKIP=0
SECTION=""

# Colors (unless NO_COLOR is set)
if [ -z "$NO_COLOR" ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN="" RED="" YELLOW="" CYAN="" BOLD="" RESET=""
fi

section() {
  SECTION="$1"
  echo ""
  echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"
}

subsection() {
  echo -e "\n${BOLD}--- $1 ---${RESET}"
}

check() {
  local desc="$1"
  local result="$2"  # 0 = pass, 1 = fail
  if [ "$result" -eq 0 ]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    FAIL=$((FAIL + 1))
  fi
}

skip() {
  local desc="$1"
  local reason="$2"
  echo -e "  ${YELLOW}⊘${RESET} $desc ${YELLOW}($reason)${RESET}"
  SKIP=$((SKIP + 1))
}

# Check if a file exists
check_file() {
  local path="$1"
  local desc="${2:-$path exists}"
  if [ -f "$path" ]; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check if a directory exists
check_dir() {
  local path="$1"
  local desc="${2:-$path exists}"
  if [ -d "$path" ]; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a file does NOT exist
check_no_file() {
  local path="$1"
  local desc="${2:-$path does not exist}"
  if [ ! -f "$path" ]; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a directory does NOT exist
check_no_dir() {
  local path="$1"
  local desc="${2:-$path does not exist}"
  if [ ! -d "$path" ]; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a file contains a string
check_contains() {
  local path="$1"
  local pattern="$2"
  local desc="${3:-$path contains '$pattern'}"
  if [ -f "$path" ] && grep -q "$pattern" "$path" 2>/dev/null; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a file does NOT contain a string
check_not_contains() {
  local path="$1"
  local pattern="$2"
  local desc="${3:-$path does not contain '$pattern'}"
  if [ ! -f "$path" ] || ! grep -q "$pattern" "$path" 2>/dev/null; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a glob pattern matches at least one file
check_glob() {
  local pattern="$1"
  local desc="${2:-files matching $pattern exist}"
  # Use compgen to check glob without zsh issues
  if ls $pattern 1>/dev/null 2>&1; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a glob pattern matches NO files
check_no_glob() {
  local pattern="$1"
  local desc="${2:-no files matching $pattern}"
  if ls $pattern 1>/dev/null 2>&1; then
    check "$desc" 1
  else
    check "$desc" 0
  fi
}

# Check that a command succeeds (exit 0)
check_cmd() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a command fails (non-zero exit)
check_cmd_fails() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    check "$desc" 1
  else
    check "$desc" 0
  fi
}

# Check that command output contains a string
check_output_contains() {
  local desc="$1"
  local pattern="$2"
  shift 2
  local output
  output=$("$@" 2>&1)
  if echo "$output" | grep -q "$pattern"; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check that a JSON file is valid JSON
check_valid_json() {
  local path="$1"
  local desc="${2:-$path is valid JSON}"
  if [ -f "$path" ] && python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
    check "$desc" 0
  else
    check "$desc" 1
  fi
}

# Check relay is reachable
check_relay() {
  local url="${1:-http://localhost:4000}"
  if curl -sf "$url" >/dev/null 2>&1; then
    check "Relay reachable at $url" 0
  else
    check "Relay reachable at $url" 1
  fi
}

# Print summary
summary() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${GREEN}  Passed:  $PASS${RESET}"
  if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}  Failed:  $FAIL${RESET}"
  else
    echo -e "  Failed:  0"
  fi
  if [ "$SKIP" -gt 0 ]; then
    echo -e "${YELLOW}  Skipped: $SKIP${RESET}"
  fi
  echo -e "${BOLD}  Total:   $((PASS + FAIL + SKIP))${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  if [ "$FAIL" -gt 0 ]; then
    return 1
  fi
  return 0
}
