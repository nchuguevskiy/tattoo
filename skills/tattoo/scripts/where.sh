#!/usr/bin/env bash
# Used by the tattoo skill: print where this session's tattoo lives and whether it exists.
id="${1:-}"
case "$id" in '${'*) id="" ;; esac
id="${id:-${CLAUDE_CODE_SESSION_ID:-}}"
dir="${TATTOO_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tattoo}"
case "$id" in
  "" | *[!A-Za-z0-9-]*)
    echo "unknown session id; use $dir/<id>.md, where <id> is the name of this session's transcript ~/.claude/projects/<project>/<id>.jsonl"
    exit 0 ;;
esac
mkdir -p "$dir"
file="$dir/$id.md"
if [ -s "$file" ]; then
  echo "$file (exists, $(wc -c <"$file" | tr -d ' ') bytes: Read it first, carry over everything still true)"
else
  echo "$file (new)"
fi
