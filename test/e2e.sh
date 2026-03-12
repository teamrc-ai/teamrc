#!/bin/bash
# test/e2e.sh — End-to-end test for teamrc
# Tests the relay API with curl
# Requires: mix, postgres running, TEAMRC_RELAY or defaults to localhost:4002
set -e

echo "=== teamrc E2E Test ==="

cd "$(dirname "$0")/.."

# Preflight checks
for cmd in mix curl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: '$cmd' is required but not found. Please install it first."
    exit 1
  fi
done

# 1. Start relay in background
echo "Starting relay..."
cd teamrc
PHX_SERVER=true PORT=4002 MIX_ENV=test mix phx.server &
RELAY_PID=$!
cd ..

cleanup() {
  kill $RELAY_PID 2>/dev/null || true
  wait $RELAY_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for server to be ready
RELAY_URL="${TEAMRC_RELAY:-http://localhost:4002}"
echo "Waiting for relay at $RELAY_URL..."
for i in $(seq 1 15); do
  if curl -s "$RELAY_URL/" > /dev/null 2>&1; then
    echo "Relay is ready."
    break
  fi
  if [ "$i" = "15" ]; then
    echo "ERROR: Relay failed to start within 15s."
    exit 1
  fi
  sleep 1
done

PASS=0
FAIL=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

TOKEN="trc_ak_e2etest_$(date +%s)"

# 2. Create team via API (POST /api/teams)
echo ""
echo "--- Test: Create team ---"
RESPONSE=$(curl -s -X POST "$RELAY_URL/api/teams" \
  -H "Content-Type: application/json" \
  -H "x-trc-signature: test" \
  -d "{
    \"token\": \"$TOKEN\",
    \"team\": {
      \"name\": \"e2e-project\",
      \"members\": [
        {\"name\": \"architect\", \"role\": \"System design\"},
        {\"name\": \"coder\", \"role\": \"Implementation\"}
      ]
    }
  }")

if echo "$RESPONSE" | grep -q '"team"'; then
  pass "Team created"
else
  fail "Team creation failed: $RESPONSE"
fi

# 3. Get team (GET /api/teams/:token)
echo ""
echo "--- Test: Get team ---"
TEAM=$(curl -s "$RELAY_URL/api/teams/$TOKEN" \
  -H "x-trc-signature: test")

if echo "$TEAM" | grep -q "e2e-project"; then
  pass "Team retrieved"
else
  fail "Team retrieval failed: $TEAM"
fi

if echo "$TEAM" | grep -q "architect"; then
  pass "Team has architect member"
else
  fail "Missing architect member"
fi

# 4. Get team head (GET /api/teams/:token/head)
echo ""
echo "--- Test: Get team head ---"
HEAD=$(curl -s "$RELAY_URL/api/teams/$TOKEN/head" \
  -H "x-trc-signature: test")

if echo "$HEAD" | grep -q '"hash"'; then
  pass "Team head returns hash"
else
  fail "Team head failed: $HEAD"
fi

# 5. Update team — add a member
echo ""
echo "--- Test: Update team ---"
UPDATE_RESP=$(curl -s -X POST "$RELAY_URL/api/teams" \
  -H "Content-Type: application/json" \
  -H "x-trc-signature: test" \
  -d "{
    \"token\": \"$TOKEN\",
    \"team\": {
      \"name\": \"e2e-project\",
      \"members\": [
        {\"name\": \"architect\", \"role\": \"System design\"},
        {\"name\": \"coder\", \"role\": \"Implementation\"},
        {\"name\": \"reviewer\", \"role\": \"Code review\"}
      ]
    }
  }")

if echo "$UPDATE_RESP" | grep -q "reviewer"; then
  pass "Team updated with new member"
else
  fail "Team update failed: $UPDATE_RESP"
fi

# 6. Verify hash changed after update
echo ""
echo "--- Test: Hash changed after update ---"
HEAD2=$(curl -s "$RELAY_URL/api/teams/$TOKEN/head" \
  -H "x-trc-signature: test")

HASH1=$(echo "$HEAD" | grep -o '"hash":"[^"]*"' | head -1)
HASH2=$(echo "$HEAD2" | grep -o '"hash":"[^"]*"' | head -1)

if [ "$HASH1" != "$HASH2" ]; then
  pass "Hash changed after update"
else
  fail "Hash should have changed after update"
fi

# 7. Get nonexistent team
echo ""
echo "--- Test: Get nonexistent team ---"
NOT_FOUND=$(curl -s -o /dev/null -w "%{http_code}" "$RELAY_URL/api/teams/trc_ak_doesnotexist" \
  -H "x-trc-signature: test")

if [ "$NOT_FOUND" = "404" ]; then
  pass "Nonexistent team returns 404"
else
  fail "Expected 404, got $NOT_FOUND"
fi

# 8. Test LiveView loads
echo ""
echo "--- Test: Web UI renders ---"
HTML=$(curl -s "$RELAY_URL/")
if echo "$HTML" | grep -qi "teamrc\|Create a Team\|team"; then
  pass "Web UI renders"
else
  fail "Web UI not rendering"
fi

# Summary
echo ""
echo "================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
