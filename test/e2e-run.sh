#!/usr/bin/env bash
#
# E2E test orchestration: boot Phoenix with real auth, run Node.js tests, teardown.
#
# Usage: bash test/e2e-run.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
E2E_DIR="$ROOT_DIR/test/e2e"
PHOENIX_DIR="$ROOT_DIR/teamrc"
PORT=4002
PHOENIX_PID=""

cleanup() {
  if [ -n "$PHOENIX_PID" ]; then
    echo ">> Stopping Phoenix (PID $PHOENIX_PID)..."
    kill "$PHOENIX_PID" 2>/dev/null || true
    wait "$PHOENIX_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ─── Prerequisites ───

echo ">> Checking prerequisites..."

if ! command -v mix &>/dev/null; then
  echo "ERROR: mix not found. Install Elixir first."
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "ERROR: node not found. Install Node.js first."
  exit 1
fi

# Check postgres is running
if ! pg_isready -q 2>/dev/null; then
  echo "ERROR: PostgreSQL is not running."
  exit 1
fi

# ─── Install E2E deps ───

echo ">> Installing E2E dependencies..."
cd "$E2E_DIR"
npm install --silent

CLI_E2E_DIR="$E2E_DIR/cli"
if [ -d "$CLI_E2E_DIR" ]; then
  echo ">> Installing CLI E2E dependencies..."
  cd "$CLI_E2E_DIR"
  npm install --silent
fi

# ─── Reset database ───

echo ">> Resetting test database..."
cd "$PHOENIX_DIR"
MIX_ENV=test mix ecto.reset --quiet 2>/dev/null || MIX_ENV=test mix ecto.reset

# ─── Start Phoenix ───

echo ">> Starting Phoenix on port $PORT with real auth..."
cd "$PHOENIX_DIR"
MIX_ENV=test PHX_SERVER=true SKIP_AUTH=false mix phx.server &
PHOENIX_PID=$!

# Poll until ready
echo ">> Waiting for server..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
    echo ">> Server ready!"
    break
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "ERROR: Server did not become ready within ${TIMEOUT}s"
  exit 1
fi

# ─── Run API-level E2E tests ───

echo ""
echo ">> Running API-level E2E tests..."
cd "$E2E_DIR"
API_EXIT=0
npx tsx --test ./*.test.ts || API_EXIT=$?

# ─── Run CLI subprocess E2E tests ───

CLI_EXIT=0
if [ -d "$CLI_E2E_DIR" ]; then
  echo ""
  echo ">> Running CLI subprocess E2E tests..."
  cd "$CLI_E2E_DIR"
  npx tsx --test ./*.test.ts || CLI_EXIT=$?
fi

# ─── Report ───

TEST_EXIT=$((API_EXIT + CLI_EXIT))

echo ""
if [ $API_EXIT -eq 0 ]; then
  echo ">> API E2E tests: PASSED"
else
  echo ">> API E2E tests: FAILED (exit code $API_EXIT)"
fi

if [ $CLI_EXIT -eq 0 ]; then
  echo ">> CLI E2E tests: PASSED"
else
  echo ">> CLI E2E tests: FAILED (exit code $CLI_EXIT)"
fi

if [ $TEST_EXIT -eq 0 ]; then
  echo ""
  echo ">> All E2E tests passed!"
fi

exit $TEST_EXIT
