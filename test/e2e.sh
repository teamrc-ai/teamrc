#!/bin/bash
# test/e2e.sh — End-to-end test for teamrc
# Tests the relay API with curl (auth skipped in test mode)
set -e

echo "=== teamrc E2E Test ==="

cd "$(dirname "$0")/.."

# 1. Start relay in background
echo "Starting relay..."
cd relay
PHX_SERVER=true PORT=4002 MIX_ENV=test mix phx.server &
RELAY_PID=$!
cd ..

cleanup() {
  kill $RELAY_PID 2>/dev/null || true
  wait $RELAY_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for server to be ready
echo "Waiting for relay to start..."
for i in $(seq 1 10); do
  if curl -s http://localhost:4002/api/teams/tb_ak_nonexistent -H "x-tb-signature: test" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

RELAY_URL="http://localhost:4002"
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

# 2. Create team via API
echo ""
echo "--- Test: Create team ---"
RESPONSE=$(curl -s -X POST "$RELAY_URL/api/teams" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "team": {
      "name": "test-project",
      "members": [
        {"name": "architect", "role": "System design"},
        {"name": "coder", "role": "Implementation"}
      ]
    }
  }')

if echo "$RESPONSE" | grep -q '"status"'; then
  pass "Team created"
else
  fail "Team creation failed: $RESPONSE"
fi

# 3. Get team
echo ""
echo "--- Test: Get team ---"
TEAM=$(curl -s "$RELAY_URL/api/teams/tb_ak_testtoken123" \
  -H "x-tb-signature: test")

if echo "$TEAM" | grep -q "test-project"; then
  pass "Team retrieved"
else
  fail "Team retrieval failed: $TEAM"
fi

if echo "$TEAM" | grep -q "architect"; then
  pass "Team has architect member"
else
  fail "Missing architect member"
fi

# 4. Get nonexistent team
echo ""
echo "--- Test: Get nonexistent team ---"
NOT_FOUND=$(curl -s -o /dev/null -w "%{http_code}" "$RELAY_URL/api/teams/tb_ak_doesnotexist" \
  -H "x-tb-signature: test")

if [ "$NOT_FOUND" = "404" ]; then
  pass "Nonexistent team returns 404"
else
  fail "Expected 404, got $NOT_FOUND"
fi

# 5. Push memory from claude-code
echo ""
echo "--- Test: Push memory ---"
PUSH_RESP=$(curl -s -X POST "$RELAY_URL/api/push" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "claude-code",
    "entry": {
      "type": "memory",
      "content": "Auth bug fixed via JWT rotation",
      "timestamp": "2026-03-05T12:00:00Z"
    }
  }')

if echo "$PUSH_RESP" | grep -q '"status"'; then
  pass "Memory pushed"
else
  fail "Push failed: $PUSH_RESP"
fi

# 6. Pull from openclaw — should get the entry
echo ""
echo "--- Test: Pull memory from other platform ---"
PULL=$(curl -s -X POST "$RELAY_URL/api/pull" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw"
  }')

if echo "$PULL" | grep -q "JWT rotation"; then
  pass "Memory synced to other platform"
else
  fail "Memory not found in pull: $PULL"
fi

# 7. Pull again — should be empty (already delivered)
echo ""
echo "--- Test: Second pull is empty ---"
PULL2=$(curl -s -X POST "$RELAY_URL/api/pull" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw"
  }')

if echo "$PULL2" | grep -q '"entries":\[\]'; then
  pass "Buffer emptied after delivery"
else
  fail "Buffer not emptied: $PULL2"
fi

# 8. Pull from same platform — should not see own entries
echo ""
echo "--- Test: Self-filtering (no echo) ---"
# Push another entry
curl -s -X POST "$RELAY_URL/api/push" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw",
    "entry": {"type": "memory", "content": "OpenClaw finding", "timestamp": "2026-03-05T12:01:00Z"}
  }' > /dev/null

SELF_PULL=$(curl -s -X POST "$RELAY_URL/api/pull" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw"
  }')

if echo "$SELF_PULL" | grep -q '"entries":\[\]'; then
  pass "Self-filtering works (no echo)"
else
  fail "Self-filtering broken: $SELF_PULL"
fi

# 9. Sync with hashes
echo ""
echo "--- Test: Sync detects changes ---"
# Set hashes for openclaw
curl -s -X POST "$RELAY_URL/api/sync" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw",
    "hashes": {"memory.md": "hash_aaa", "team.json": "hash_bbb"}
  }' > /dev/null

# Sync from claude-code with different hash
SYNC_RESP=$(curl -s -X POST "$RELAY_URL/api/sync" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "claude-code",
    "hashes": {"memory.md": "hash_aaa", "team.json": "hash_ccc"}
  }')

if echo "$SYNC_RESP" | grep -q "changes"; then
  pass "Sync returns changes"
else
  fail "Sync failed: $SYNC_RESP"
fi

# 10. Test LiveView loads
echo ""
echo "--- Test: LiveView renders ---"
HTML=$(curl -s "$RELAY_URL/")
if echo "$HTML" | grep -q "teamrc\|Create a Team\|team"; then
  pass "LiveView renders"
else
  fail "LiveView not rendering"
fi

# Summary
echo ""
echo "================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
