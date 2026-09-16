#!/usr/bin/env bash
# Remove a manual tattoo install: the skill, the hook script and its settings.json entry.
# Tattoos themselves (~/.local/state/tattoo) and CLAUDE.md are left alone.
set -euo pipefail

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"

rm -rf "$claude_dir/skills/tattoo"
rm -f "$claude_dir/hooks/tattoo-restore.sh"
echo "removed:  $claude_dir/skills/tattoo, $claude_dir/hooks/tattoo-restore.sh"

if [ -f "$settings" ]; then
  cp "$settings" "$settings.bak-tattoo"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
hooks = data.get("hooks", {})
groups = hooks.get("SessionStart", [])
kept = []
for g in groups:
    g["hooks"] = [h for h in g.get("hooks", []) if "tattoo-restore.sh" not in h.get("command", "")]
    if g["hooks"]:
        kept.append(g)
if kept:
    hooks["SessionStart"] = kept
else:
    hooks.pop("SessionStart", None)
if not hooks:
    data.pop("hooks", None)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  elif command -v jq >/dev/null 2>&1; then
    tmp="$settings.tmp-tattoo"
    jq '
      if .hooks.SessionStart then
        .hooks.SessionStart |= (map(.hooks |= map(select((.command // "") | contains("tattoo-restore.sh") | not)))
                                | map(select(.hooks | length > 0)))
        | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
      else . end' "$settings" >"$tmp" && mv "$tmp" "$settings"
  else
    echo "need python3 or jq; remove the tattoo-restore.sh hook from $settings by hand" >&2
    exit 1
  fi
  echo "settings: $settings (hook removed, backup: $settings.bak-tattoo)"
fi

echo "kept:     ${TATTOO_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tattoo} (delete it if you want your tattoos gone)"
