#!/bin/bash
# clean-slate.sh — Remove ALL teamrc + TeamBridge state for a fresh test run
# Run from the project root. Safe to run multiple times.
#
# Unlike uninstall.sh, this also strips teamrc sections from shared files
# (CLAUDE.md, .codex/config.toml, openclaw.json) so no manual cleanup is needed.
set -e

echo "=== teamrc clean slate ==="
echo ""

removed=0

remove_if_exists() {
  if [ -e "$1" ]; then
    rm -rf "$1"
    echo "  Removed: $1"
    removed=$((removed + 1))
  fi
}

# --- Config directories ---
echo "Config directories..."
remove_if_exists "$HOME/.teamrc"
remove_if_exists "$HOME/.teambridge"

# --- Project config files ---
echo "Project config..."
remove_if_exists ".teamrc.yaml"
remove_if_exists "agent-team.yaml"
remove_if_exists ".claude/teamrc-knowledge.md"

# --- Project state directory ---
echo "Project state..."
remove_if_exists ".teamrc"

# --- Claude Code ---
echo "Claude Code..."
for f in .claude/agents/trc-*.md .claude/agents/tb-*.md; do
  remove_if_exists "$f"
done
for f in .claude/rules/trc-*.md; do
  remove_if_exists "$f"
done
for d in .claude/skills/trc-*; do
  remove_if_exists "$d"
done

# CLAUDE.md — strip teamrc section between markers
if [ -f "CLAUDE.md" ] && grep -q "<!-- teamrc -->" "CLAUDE.md" 2>/dev/null; then
  sed -i '' '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' "CLAUDE.md"
  echo "  Cleaned: CLAUDE.md (removed teamrc section)"
  removed=$((removed + 1))
fi

# --- Cursor ---
echo "Cursor..."
for f in .cursor/agents/trc-*.md .cursor/agents/tb-*.md; do
  remove_if_exists "$f"
done
for f in .cursor/rules/trc-*.mdc .cursor/rules/tb-*.mdc; do
  remove_if_exists "$f"
done
for d in .cursor/skills/trc-* .cursor/skills/tb-*; do
  remove_if_exists "$d"
done
if [ -f ".cursor/AGENTS.md" ] && grep -q "teamrc\|trc-" ".cursor/AGENTS.md" 2>/dev/null; then
  remove_if_exists ".cursor/AGENTS.md"
fi

# --- Codex ---
echo "Codex..."
for f in .codex/agents/trc-*.toml .codex/agents/tb-*.toml; do
  remove_if_exists "$f"
done

# .codex/config.toml — strip teamrc section between markers
if [ -f ".codex/config.toml" ] && grep -q "# --- teamrc start ---" ".codex/config.toml" 2>/dev/null; then
  sed -i '' '/# --- teamrc start ---/,/# --- teamrc end ---/d' ".codex/config.toml"
  echo "  Cleaned: .codex/config.toml (removed teamrc section)"
  removed=$((removed + 1))
fi

# AGENTS.md (shared by Codex + OpenClaw) — strip teamrc section
if [ -f "AGENTS.md" ] && grep -q "<!-- teamrc -->" "AGENTS.md" 2>/dev/null; then
  sed -i '' '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' "AGENTS.md"
  echo "  Cleaned: AGENTS.md (removed teamrc section)"
  removed=$((removed + 1))
fi

# --- Gemini ---
# Agents: .gemini/agents/
# Skills: .agents/skills/ (Gemini CLI) + .agent/skills/ (Antigravity)
echo "Gemini..."
for f in .gemini/agents/trc-*.md; do
  remove_if_exists "$f"
done

# GEMINI.md — strip teamrc section
if [ -f "GEMINI.md" ] && grep -q "<!-- teamrc -->" "GEMINI.md" 2>/dev/null; then
  sed -i '' '/<!-- teamrc -->/,/<!-- \/teamrc -->/d' "GEMINI.md"
  echo "  Cleaned: GEMINI.md (removed teamrc section)"
  removed=$((removed + 1))
fi

# --- Gemini CLI skills (.agents/skills/) + Antigravity skills (.agent/skills/) ---
# These directories are shared between Gemini CLI and OpenClaw/OpenHands.
echo "Shared skill dirs (.agents/, .agent/)..."
for f in .agents/agents/trc-*.md; do
  remove_if_exists "$f"
done
for d in .agents/skills/trc-*; do
  remove_if_exists "$d"
done
for d in .agent/skills/trc-*; do
  remove_if_exists "$d"
done
for f in "$HOME"/.agents/agents/trc-*.md; do
  remove_if_exists "$f"
done
for d in "$HOME"/.agents/skills/trc-*; do
  remove_if_exists "$d"
done

# --- OpenClaw ---
echo "OpenClaw..."

# ~/.openclaw/ dirs (workspace-trc-*, agents/trc-*, skills/trc-*)
for d in "$HOME"/.openclaw/workspace-trc-* "$HOME"/.openclaw/workspace-tb-*; do
  remove_if_exists "$d"
done
for d in "$HOME"/.openclaw/agents/trc-* "$HOME"/.openclaw/agents/tb-*; do
  remove_if_exists "$d"
done
for d in "$HOME"/.openclaw/skills/trc-* "$HOME"/.openclaw/skills/tb-*; do
  remove_if_exists "$d"
done
remove_if_exists "$HOME/.openclaw/teamrc-knowledge.md"

# ~/.openclaw/openclaw.json — remove trc-/tb- agent entries
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_JSON" ] && grep -q "trc-\|tb-" "$OPENCLAW_JSON" 2>/dev/null; then
  python3 -c "
import json
with open('$OPENCLAW_JSON') as f:
    data = json.load(f)
agents = data.get('agents', {})
agent_list = agents.get('list', [])
cleaned = [a for a in agent_list if not a.get('id','').startswith(('trc-','tb-'))]
removed_count = len(agent_list) - len(cleaned)
if removed_count > 0:
    agents['list'] = cleaned
    data['agents'] = agents
    with open('$OPENCLAW_JSON', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print(f'  Cleaned: $OPENCLAW_JSON (removed {removed_count} agent(s))')
"
  removed=$((removed + 1))
fi

# --- Claude settings ---
echo "Claude settings..."
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "teambridge\|teamrc\|AGENT_TEAMS" "$SETTINGS" 2>/dev/null; then
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
"
  removed=$((removed + 1))
fi

# --- Summary ---
echo ""
echo "Done. Removed/cleaned $removed item(s)."

# Verify nothing remains
remaining=$(grep -rl "teamrc\|TeamBridge\|trc-\|tb-" \
  .claude/agents/ .cursor/agents/ .codex/agents/ .gemini/agents/ .agents/agents/ .agent/skills/ \
  2>/dev/null | wc -l | tr -d ' ')
if [ "$remaining" != "0" ]; then
  echo ""
  echo "WARNING: $remaining file(s) still reference teamrc/TeamBridge."
  grep -rl "teamrc\|TeamBridge\|trc-\|tb-" \
    .claude/agents/ .cursor/agents/ .codex/agents/ .gemini/agents/ .agents/agents/ .agent/skills/ \
    2>/dev/null | sed 's/^/  /'
fi
