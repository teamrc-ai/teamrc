#!/bin/bash
# prereqs.sh — Check test prerequisites before running the test plan
# Usage: bash scripts/verify/prereqs.sh
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Prerequisites"

RELAY_URL="${TEAMRC_RELAY:-http://localhost:4000}"
IS_LOCAL=false
if echo "$RELAY_URL" | grep -q "localhost\|127\.0\.0\.1"; then
  IS_LOCAL=true
fi

# PostgreSQL (only required for local relay)
if [ "$IS_LOCAL" = true ]; then
  if pg_isready >/dev/null 2>&1; then
    check "PostgreSQL running" 0
  else
    check "PostgreSQL running" 1
  fi
else
  skip "PostgreSQL check" "not needed for cloud relay ($RELAY_URL)"
fi

# Relay
if curl -sf "$RELAY_URL" >/dev/null 2>&1; then
  check "Relay running at $RELAY_URL" 0
else
  check "Relay running at $RELAY_URL" 1
fi

# Database migrations (only for local relay)
if [ "$IS_LOCAL" = true ]; then
  if command -v mix >/dev/null 2>&1; then
    if cd teamrc && mix ecto.migrations 2>/dev/null | grep -q "down"; then
      check "Database migrations up to date" 1
      echo "    Run: cd teamrc && mix ecto.migrate"
    else
      check "Database migrations up to date" 0
    fi
    cd - >/dev/null 2>&1
  else
    skip "Database migration check" "mix not available"
  fi
else
  skip "Database migration check" "not needed for cloud relay ($RELAY_URL)"
fi

# CLI built
if [ -f "cli/dist/index.js" ]; then
  check "CLI built (cli/dist/index.js)" 0
else
  check "CLI built (cli/dist/index.js)" 1
fi

# Node
if command -v node >/dev/null 2>&1; then
  check "Node.js installed ($(node -v))" 0
else
  check "Node.js installed" 1
fi

# npx
if command -v npx >/dev/null 2>&1; then
  check "npx available" 0
else
  check "npx available" 1
fi

# python3 (used for JSON validation)
if command -v python3 >/dev/null 2>&1; then
  check "python3 available" 0
else
  check "python3 available" 1
fi

# curl
if command -v curl >/dev/null 2>&1; then
  check "curl available" 0
else
  check "curl available" 1
fi

summary
