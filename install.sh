#!/usr/bin/env bash
# Manual install of tattoo without the plugin system.
#
#   ./install.sh                         English skill + hook
#   ./install.sh --lang ru               Russian skill + hook
#   ./install.sh --compact-instructions  also append the Compact instructions block to CLAUDE.md
#
# Installs:
#   <claude dir>/skills/tattoo/SKILL.md
#   <claude dir>/hooks/tattoo-restore.sh
#   a SessionStart hook group (matcher "compact") in <claude dir>/settings.json
# where <claude dir> is $CLAUDE_CONFIG_DIR or ~/.claude. Safe to re-run; re-running upgrades.
set -euo pipefail

lang=en
compact_instructions=0
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) lang="${2:-}"; shift 2 ;;
    --lang=*) lang="${1#--lang=}"; shift ;;
    --compact-instructions) compact_instructions=1; shift ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
hook="$claude_dir/hooks/tattoo-restore.sh"
# Number of hook copies; each prints one part of the tattoo (see hooks/restore.sh).
slots=8

case "$lang" in
  en) skill_src="$src/skills/tattoo/SKILL.md"; instructions_src="$src/templates/compact-instructions.md" ;;
  ru) skill_src="$src/i18n/ru/SKILL.md"; instructions_src="$src/i18n/ru/compact-instructions.md" ;;
  *) echo "unsupported --lang: $lang (en, ru)" >&2; exit 2 ;;
esac

mkdir -p "$claude_dir/skills/tattoo/scripts" "$claude_dir/hooks"
cp "$skill_src" "$claude_dir/skills/tattoo/SKILL.md"
cp "$src/skills/tattoo/scripts/where.sh" "$claude_dir/skills/tattoo/scripts/where.sh"
cp "$src/hooks/restore.sh" "$hook"
chmod +x "$hook"
echo "skill:    $claude_dir/skills/tattoo/SKILL.md ($lang)"
echo "hook:     $hook"

# Register the hook: drop earlier tattoo entries, then add one group with $slots
# copies. Everything else in settings.json is kept.
[ -f "$settings" ] || echo '{}' >"$settings"
cp "$settings" "$settings.bak-tattoo"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$settings" "$hook" "$slots" <<'EOF'
import json, sys
path, hook, slots = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path) as f:
    data = json.load(f)
groups = data.setdefault("hooks", {}).setdefault("SessionStart", [])
kept = []
for g in groups:
    g["hooks"] = [h for h in g.get("hooks", []) if "tattoo-restore.sh" not in h.get("command", "")]
    if g["hooks"]:
        kept.append(g)
kept.append({"matcher": "compact", "hooks": [
    {"type": "command", "command": f'bash "{hook}" {i} {slots}', "timeout": 10}
    for i in range(1, slots + 1)]})
data["hooks"]["SessionStart"] = kept
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF
elif command -v jq >/dev/null 2>&1; then
  tmp="$settings.tmp-tattoo"
  jq --arg hook "$hook" --argjson slots "$slots" '
    .hooks.SessionStart = (
      [(.hooks.SessionStart // [])[]
        | .hooks |= map(select((.command // "") | contains("tattoo-restore.sh") | not))
        | select(.hooks | length > 0)]
      + [{matcher: "compact", hooks: [range(1; $slots + 1) as $i
          | {type: "command", command: "bash \"\($hook)\" \($i) \($slots)", timeout: 10}]}]
    )' "$settings" >"$tmp" && mv "$tmp" "$settings"
else
  echo "need python3 or jq to edit $settings" >&2
  echo "add a SessionStart group with matcher \"compact\" and $slots command hooks:" >&2
  echo "  bash \"$hook\" 1 $slots   ...   bash \"$hook\" $slots $slots" >&2
  exit 1
fi
echo "settings: $settings (SessionStart:compact, $slots hook copies)"
echo "backup:   $settings.bak-tattoo"

if [ "$compact_instructions" = 1 ]; then
  md="$claude_dir/CLAUDE.md"
  if [ -f "$md" ] && grep -qi '^#\{1,6\} *compact instructions' "$md"; then
    echo "CLAUDE.md: $md already has a Compact instructions section; merge $instructions_src by hand"
  else
    cat "$instructions_src" >>"$md"
    echo "CLAUDE.md: $md (Compact instructions appended)"
  fi
fi

echo
echo "Done. Restart Claude Code, then: /tattoo, /compact."
