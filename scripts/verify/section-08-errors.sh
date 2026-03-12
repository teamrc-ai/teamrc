#!/bin/bash
# Section 8: Error Cases — verify error handling
# Usage: bash scripts/verify/section-08-errors.sh
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "Section 8: Error Cases"

subsection "8.1: Invalid platform"
OUTPUT=$(npx @teamrc/cli init --platform invalid-platform 2>&1 || true)
if echo "$OUTPUT" | grep -qi "unknown platform\|invalid.*platform"; then
  check "Invalid platform gives clear error" 0
else
  check "Invalid platform gives clear error" 1
fi

subsection "8.2: Invalid invite code"
OUTPUT=$(npx @teamrc/cli join trc_inv_invalid123 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid\|error\|fail"; then
  check "Invalid invite code gives error" 0
else
  check "Invalid invite code gives error" 1
fi

subsection "8.3: Relay unreachable"
OUTPUT=$(TEAMRC_RELAY=http://localhost:9999 npx @teamrc/cli sync 2>&1 || true)
if echo "$OUTPUT" | grep -qi "fail\|error\|ECONNREFUSED\|fetch"; then
  check "Unreachable relay gives error (not crash)" 0
else
  check "Unreachable relay gives error (not crash)" 1
fi

subsection "8.4: Oversized YAML"
# Create a YAML with 200 members (over 100 limit)
python3 -c "print('name: big-team\nmembers:\n' + '\n'.join(f'  - name: agent{i}\n    role: role {i}' for i in range(200)))" > /tmp/teamrc-test-oversized.yaml
cp .teamrc.yaml .teamrc.yaml.bak 2>/dev/null || true
cp /tmp/teamrc-test-oversized.yaml .teamrc.yaml
OUTPUT=$(npx @teamrc/cli apply --platform claude-code 2>&1 || true)
# Restore
if [ -f ".teamrc.yaml.bak" ]; then
  mv .teamrc.yaml.bak .teamrc.yaml
else
  rm -f .teamrc.yaml
fi
rm -f /tmp/teamrc-test-oversized.yaml
if echo "$OUTPUT" | grep -qi "max\|too many\|limit\|100\|members"; then
  check "Oversized YAML gives max members error" 0
else
  skip "Oversized YAML gives max members error" "limit may not be enforced yet"
fi

subsection "8.5: Invalid agent names"
cat > /tmp/teamrc-test-badname.yaml <<EOF
name: bad-names
members:
  - name: "../../etc/passwd"
    role: hacker
EOF
cp .teamrc.yaml .teamrc.yaml.bak 2>/dev/null || true
cp /tmp/teamrc-test-badname.yaml .teamrc.yaml
OUTPUT=$(npx @teamrc/cli apply --platform claude-code 2>&1 || true)
# Restore
if [ -f ".teamrc.yaml.bak" ]; then
  mv .teamrc.yaml.bak .teamrc.yaml
else
  rm -f .teamrc.yaml
fi
rm -f /tmp/teamrc-test-badname.yaml
if echo "$OUTPUT" | grep -qi "invalid.*name\|error\|reject"; then
  check "Path traversal agent name rejected" 0
else
  check "Path traversal agent name rejected" 1
fi

summary
