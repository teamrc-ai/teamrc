#!/bin/bash
# Section 6: Catalog & Team Management — verify list-templates, list-agents, add-member
# Usage: bash scripts/verify/section-06-catalog.sh
# Requires: CLI built, relay running, team initialized (Section 1)
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

CLI="npx @teamrc/cli"

section "Section 6: Catalog & Team Management"

# ---------------------------------------------------------------------------
# 6.1: list-templates
# ---------------------------------------------------------------------------
subsection "6.1: list-templates"

OUTPUT=$($CLI list-templates 2>&1 || true)
if echo "$OUTPUT" | grep -q "fullstack"; then
  check "list-templates shows fullstack template" 0
else
  check "list-templates shows fullstack template" 1
fi

if echo "$OUTPUT" | grep -q "backend"; then
  check "list-templates shows backend template" 0
else
  check "list-templates shows backend template" 1
fi

if echo "$OUTPUT" | grep -q "custom"; then
  check "list-templates shows custom template" 0
else
  check "list-templates shows custom template" 1
fi

if echo "$OUTPUT" | grep -q "templates"; then
  check "list-templates shows template count in footer" 0
else
  check "list-templates shows template count in footer" 1
fi

# JSON output
JSON_OUTPUT=$($CLI list-templates --json 2>&1 || true)
if echo "$JSON_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d)>0; assert 'id' in d[0]; assert 'members' in d[0]" 2>/dev/null; then
  check "list-templates --json returns valid JSON with id and members" 0
else
  check "list-templates --json returns valid JSON with id and members" 1
fi

# ---------------------------------------------------------------------------
# 6.2: list-agents
# ---------------------------------------------------------------------------
subsection "6.2: list-agents"

OUTPUT=$($CLI list-agents 2>&1 || true)
if echo "$OUTPUT" | grep -q "Core Development"; then
  check "list-agents shows Core Development category" 0
else
  check "list-agents shows Core Development category" 1
fi

if echo "$OUTPUT" | grep -q "backend-dev"; then
  check "list-agents shows backend-dev" 0
else
  check "list-agents shows backend-dev" 1
fi

if echo "$OUTPUT" | grep -q "agents"; then
  check "list-agents shows agent count in footer" 0
else
  check "list-agents shows agent count in footer" 1
fi

# JSON output
JSON_OUTPUT=$($CLI list-agents --json 2>&1 || true)
if echo "$JSON_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d)>0; assert 'category' in d[0]; assert 'agents' in d[0]" 2>/dev/null; then
  check "list-agents --json returns valid JSON with category and agents" 0
else
  check "list-agents --json returns valid JSON with category and agents" 1
fi

# ---------------------------------------------------------------------------
# 6.3: add-member (by name)
# ---------------------------------------------------------------------------
subsection "6.3: add-member by name"

# Only run if a team is initialized
if [ -f ".teamrc.yaml" ]; then
  # Pick an agent that's unlikely to already be on the team
  AGENT_NAME="security-engineer"

  # Check if already present (skip if so)
  if grep -qF "$AGENT_NAME" .teamrc.yaml 2>/dev/null; then
    skip "add-member $AGENT_NAME" "already on team"
  else
    OUTPUT=$($CLI add-member "$AGENT_NAME" 2>&1 || true)
    if echo "$OUTPUT" | grep -qi "Added $AGENT_NAME"; then
      check "add-member adds agent successfully" 0
    else
      check "add-member adds agent successfully" 1
    fi

    check_contains .teamrc.yaml "$AGENT_NAME" "YAML contains new member"

    # Check agent file was created for claude-code
    if [ -d ".claude/agents" ]; then
      check_file ".claude/agents/trc-${AGENT_NAME}.md" "Agent file created for claude-code"
    else
      skip "Agent file created for claude-code" "claude-code not configured"
    fi
  fi
else
  skip "add-member by name" "no .teamrc.yaml — run Section 1 first"
fi

# ---------------------------------------------------------------------------
# 6.4: add-member duplicate check
# ---------------------------------------------------------------------------
subsection "6.4: add-member duplicate check"

if [ -f ".teamrc.yaml" ]; then
  # Try to add an agent that should exist (from the team template or 6.3)
  # Find the first member name in the YAML
  EXISTING=$(grep "name:" .teamrc.yaml | head -2 | tail -1 | sed 's/.*name: *//' | tr -d '"' | tr -d "'" | xargs)
  if [ -n "$EXISTING" ]; then
    OUTPUT=$($CLI add-member "$EXISTING" 2>&1 || true)
    if echo "$OUTPUT" | grep -qi "already"; then
      check "Duplicate member gives 'already on team' warning" 0
    else
      check "Duplicate member gives 'already on team' warning" 1
    fi
  else
    skip "Duplicate member check" "could not determine existing member name"
  fi
else
  skip "Duplicate member check" "no .teamrc.yaml"
fi

# ---------------------------------------------------------------------------
# 6.5: add-member invalid name
# ---------------------------------------------------------------------------
subsection "6.5: add-member invalid name"

OUTPUT=$($CLI add-member nonexistent-agent-xyz 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not found"; then
  check "Invalid agent name gives 'not found' error" 0
else
  check "Invalid agent name gives 'not found' error" 1
fi

summary
