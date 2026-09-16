#!/usr/bin/env bash
# tattoo: SessionStart hook, matcher "compact".
#
#   restore.sh [PART SLOTS]
#
# /tattoo writes ~/.local/state/tattoo/<session_id>.md while the context is still whole.
# Right after a compaction (manual or auto) this hook prints that file, and Claude
# Code adds SessionStart stdout to the context Claude sees.
#
# Claude Code replaces any single hook output longer than 10,000 characters with a
# 2 KB preview. So the plugin registers SLOTS copies of this hook (PART = 1..SLOTS);
# each prints one part of the tattoo, cut at line boundaries to at most
# TATTOO_PART_SIZE UTF-16 code units (default 8500), so every part fits.
# Copies run in parallel and may land in any order; parts are labelled. If the
# tattoo needs more than SLOTS parts, part 1 tells Claude where to Read the rest.
#
# Prints nothing and exits 0 when there is no tattoo, or no such part.
set -u

part="${1:-1}"
slots="${2:-1}"
budget="${TATTOO_PART_SIZE:-8500}"
case "$part$slots$budget" in *[!0-9]*) exit 0 ;; esac
[ "$part" -ge 1 ] && [ "$part" -le "$slots" ] && [ "$budget" -ge 100 ] || exit 0

input=$(cat)

session_id=""
if command -v jq >/dev/null 2>&1; then
  session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  session_id=$(printf '%s' "$input" | python3 -c \
    'import json, sys; print(json.load(sys.stdin).get("session_id", ""))' 2>/dev/null)
else
  session_id=$(printf '%s' "$input" |
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
fi

# Session ids are UUIDs. Anything else could point outside the tattoo directory.
case "$session_id" in
  "" | *[!A-Za-z0-9-]*) exit 0 ;;
esac

dir="${TATTOO_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tattoo}"
file="$dir/$session_id.md"
[ -s "$file" ] && [ -r "$file" ] || exit 0

# Split into parts of at most $budget UTF-16 code units (what Claude Code counts),
# at line boundaries; a line longer than a whole part is cut. awk runs with
# LC_ALL=C, so it sees bytes. First output line: "<total parts> <first line not
# injected>", then the text of part $part.
split=$(LC_ALL=C awk -v want="$part" -v slots="$slots" -v budget="$budget" '
  BEGIN {
    p = 1; used = 0; over = 0; buf = ""
    cont = "[" sprintf("%c", 128) "-" sprintf("%c", 191) "]"
    lead4 = "[" sprintf("%c", 240) "-" sprintf("%c", 247) "]"
  }
  # UTF-16 units of a UTF-8 string: bytes, minus continuation bytes, plus one per
  # 4-byte sequence (a surrogate pair).
  function units(s,   a, b) { a = s; b = s; return length(s) - gsub(cont, "", a) + gsub(lead4, "", b) }
  function add(s) { if (p == want) buf = buf s "\n" }
  {
    line = $0
    n = units(line)
    while (1) {
      if (used > 0 && used + n + 1 > budget) { p++; used = 0 }
      if (p == slots + 1 && over == 0) over = NR
      if (n + 1 <= budget) { add(line); used += n + 1; break }
      # Cut budget-1 bytes at most (bytes never undercount units), backing off
      # so the cut does not split a UTF-8 sequence.
      k = budget
      while (k > 1 && substr(line, k, 1) ~ ("^" cont "$")) k--
      if (k == 1) k = budget
      add(substr(line, 1, k - 1))
      used = budget
      line = substr(line, k)
      n = units(line)
    }
  }
  END { print p, over; printf "%s", buf }
' "$file" 2>/dev/null; printf x)
split="${split%x}"
meta="${split%%$'\n'*}"
body="${split#*$'\n'}"
total="${meta%% *}"
over_line="${meta#* }"
case "$total" in "" | *[!0-9]*) exit 0 ;; esac
[ "$part" -le "$total" ] || exit 0

if [ "$total" -eq 1 ]; then
  label="tattoo"
else
  label="tattoo part $part/$total"
fi

if [ "$part" -eq 1 ]; then
  # GNU stat first, BSD (macOS) stat second.
  mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "")
  age="unknown time"
  if [ -n "$mtime" ]; then
    age="$(( ($(date +%s) - mtime) / 60 )) min"
  fi
  size=$(wc -c <"$file" | tr -d ' ')
  echo "[tattoo] Session tattoo written $age before this compaction: $file ($size bytes)"
  echo "It complements the compaction summary: history, forks and decisions, problems, knowledge, user rules, open items."
  echo "Events after the tattoo are only in the summary; where the two disagree, trust the summary."
  if [ "$total" -gt 1 ]; then
    injected=$(( total < slots ? total : slots ))
    echo "The tattoo has $total parts; parts 1-$injected arrive as separate hook outputs, possibly out of order. Read them in part order."
  fi
  if [ "$total" -gt "$slots" ]; then
    echo "Parts $((slots + 1))-$total did not fit into hook output. Before continuing, Read $file from line $over_line to the end."
  fi
  echo "If any part shows \"Output too large\" instead of text, Read $file in full."
  echo "The next /tattoo overwrites this file, so carry everything still true from it into the new one."
  echo
else
  echo "[tattoo] $file"
fi
echo "--- $label ---"
printf '%s' "$body"
echo "--- end of $label ---"
