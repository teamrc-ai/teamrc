#!/bin/bash
# Section 13: Account Linking & Device Auth
# Usage: bash scripts/verify/section-13-account.sh [pre-link|post-link|post-login]
#   pre-link   — verify state before account linking (no account in config)
#   post-link  — verify state after account was linked
#   post-login — verify state after teamrc login
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

MODE="${1:-post-link}"

section "Section 13: Account Linking ($MODE)"

case "$MODE" in
  pre-link)
    subsection "Before account linking"
    check_file "$HOME/.teamrc/config.json" "config.json exists"
    check_valid_json "$HOME/.teamrc/config.json" "config.json is valid JSON"
    check_contains "$HOME/.teamrc/config.json" '"token"' "Has token"
    check_not_contains "$HOME/.teamrc/config.json" '"account"' "No account field (not yet linked)"
    check_not_contains "$HOME/.teamrc/config.json" '"email"' "No email (not yet linked)"
    ;;

  post-link|post-login)
    subsection "After account linking"
    check_file "$HOME/.teamrc/config.json" "config.json exists"
    check_valid_json "$HOME/.teamrc/config.json" "config.json is valid JSON"
    check_contains "$HOME/.teamrc/config.json" '"token"' "Has token"
    check_contains "$HOME/.teamrc/config.json" '"account"' "Has account field"
    check_contains "$HOME/.teamrc/config.json" '"email"' "Has email in account"

    # Check the email looks like an email
    EMAIL=$(python3 -c "
import json
with open('$HOME/.teamrc/config.json') as f:
    c = json.load(f)
print(c.get('account', {}).get('email', ''))
" 2>/dev/null || echo "")
    if echo "$EMAIL" | grep -q "@"; then
      check "Email looks valid: $EMAIL" 0
    else
      check "Email looks valid" 1
    fi

    # Check machineName is set
    check_contains "$HOME/.teamrc/config.json" '"machineName"' "machineName saved"
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 {pre-link|post-link|post-login}"
    exit 1
    ;;
esac

summary
