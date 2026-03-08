#!/bin/bash
# uninstall.sh — Remove all teamrc/TeamBridge artifacts from this machine
# Run from the project root. Safe to run multiple times.
set -e

echo "=== teamrc uninstall ==="
echo ""

removed=0

remove_if_exists() {
  if [ -e "$1" ]; then
    rm -rf "$1"
    echo "  Removed: $1"
    removed=$((removed + 1))
  fi
}

# 1. Config directories
echo "Cleaning config directories..."
remove_if_exists "$HOME/.teamrc"
remove_if_exists "$HOME/.teambridge"

# 2. Claude Code global settings (~/.claude/settings.json)
#    Removes: SessionStart hooks referencing teambridge/teamrc,
#    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  if grep -q "teambridge\|teamrc\|AGENT_TEAMS" "$SETTINGS" 2>/dev/null; then
    python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
changed = False
if 'env' in s and 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' in s.get('env', {}):
    del s['env']['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS']
    if not s['env']:
        del s['env']
    changed = True
if 'hooks' in s and 'SessionStart' in s.get('hooks', {}):
    hooks = s['hooks']['SessionStart']
    s['hooks']['SessionStart'] = [
        h for h in hooks
        if not any('teambridge' in hook.get('command', '') or 'teamrc' in hook.get('command', '')
                   for hook in h.get('hooks', []))
    ]
    if not s['hooks']['SessionStart']:
        del s['hooks']['SessionStart']
    if not s['hooks']:
        del s['hooks']
    changed = True
if changed:
    with open('$SETTINGS', 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    print('  Cleaned: $SETTINGS')
else:
    print('  Already clean: $SETTINGS')
"
    removed=$((removed + 1))
  fi
fi

# 3. Generated project files
echo "Cleaning project artifacts..."
remove_if_exists ".claude/team-knowledge.md"
remove_if_exists ".teamrc.yaml"

# trc-* and tb-* agent files
for f in .claude/agents/trc-*.md .claude/agents/tb-*.md; do
  remove_if_exists "$f"
done

# Remove empty .claude/agents/ dir
if [ -d ".claude/agents" ] && [ -z "$(ls -A .claude/agents 2>/dev/null)" ]; then
  rmdir .claude/agents
  echo "  Removed: .claude/agents/ (empty)"
  removed=$((removed + 1))
fi

# 4. OpenClaw workspaces
for d in "$HOME/.openclaw/workspaces/trc-"* "$HOME/.openclaw/workspaces/tb-"*; do
  remove_if_exists "$d"
done

if [ -f "openclaw.json" ] && grep -q "trc-\|tb-" "openclaw.json" 2>/dev/null; then
  python3 -c "
import json
with open('openclaw.json') as f:
    data = json.load(f)
if 'agents' in data:
    data['agents'] = [a for a in data['agents'] if not a.get('name','').startswith(('trc-','tb-'))]
    with open('openclaw.json', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('  Cleaned: openclaw.json')
"
  removed=$((removed + 1))
fi

# 5. Cursor artifacts
for f in .cursor/agents/trc-*.md .cursor/agents/tb-*.md .cursor/rules/trc-*.mdc .cursor/rules/tb-*.mdc; do
  remove_if_exists "$f"
done
for d in .cursor/skills/trc-* .cursor/skills/tb-*; do
  remove_if_exists "$d"
done
if [ -f ".cursor/AGENTS.md" ] && grep -q "teamrc\|trc-" ".cursor/AGENTS.md" 2>/dev/null; then
  remove_if_exists ".cursor/AGENTS.md"
fi

# 6. Codex artifacts
for f in .codex/agents/trc-*.toml .codex/agents/tb-*.toml; do
  remove_if_exists "$f"
done
if [ -f "AGENTS.md" ] && grep -q "teamrc\|trc-" "AGENTS.md" 2>/dev/null; then
  remove_if_exists "AGENTS.md"
fi

# 7. Gemini artifacts
if [ -f "GEMINI.md" ] && grep -q "teamrc\|trc-" "GEMINI.md" 2>/dev/null; then
  remove_if_exists "GEMINI.md"
fi

# 8. Summary + manual review guidance
echo ""
echo "Done. Removed $removed item(s)."
echo ""

# Check for remaining references that need manual review
needs_review=false

if [ -f "CLAUDE.md" ] && grep -q "teamrc\|TeamBridge\|team-knowledge\|trc-" "CLAUDE.md" 2>/dev/null; then
  echo "REVIEW NEEDED: CLAUDE.md contains teamrc references."
  echo "  Open CLAUDE.md and remove the '## teamrc Team: ...' section."
  echo "  Keep any design context or project instructions you wrote yourself."
  needs_review=true
fi

if [ -f ".codex/config.toml" ] && grep -q "trc-\|tb-" ".codex/config.toml" 2>/dev/null; then
  echo "REVIEW NEEDED: .codex/config.toml references teamrc agents."
  echo "  Remove any [[agents]] entries with trc-* or tb-* names."
  needs_review=true
fi

# Check for any project-level settings that might have teamrc references
for f in .claude/settings.json .claude/settings.local.json; do
  if [ -f "$f" ] && grep -q "teamrc\|teambridge\|trc-" "$f" 2>/dev/null; then
    echo "REVIEW NEEDED: $f may contain teamrc references."
    needs_review=true
  fi
done

if [ "$needs_review" = false ]; then
  echo "No manual review needed — all clean."
fi
