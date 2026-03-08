#!/bin/bash
# prereqs.sh — Check test prerequisites before running the test plan
# Usage: bash scripts/verify/prereqs.sh
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Prerequisites"

# PostgreSQL
if pg_isready >/dev/null 2>&1; then
  check "PostgreSQL running" 0
else
  check "PostgreSQL running" 1
fi

# Relay
if curl -sf "http://localhost:4000" >/dev/null 2>&1; then
  check "Relay running at localhost:4000" 0
else
  check "Relay running at localhost:4000" 1
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
