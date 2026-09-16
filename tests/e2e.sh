#!/usr/bin/env bash
# End-to-end check against a real Claude Code (spends a few cents of tokens).
#
#   tests/e2e.sh [model]      default model: haiku
#
# 1. starts a headless session with the plugin loaded from this checkout;
# 2. /tattoo:tattoo writes a real tattoo for that session;
# 3. appends ~32 KB of padding and an end codeword, so the hook must split it into parts;
# 4. /compact, then asks (no tools) for both codewords;
# 5. checks the transcript: every part landed verbatim after compaction.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="${1:-haiku}"
work="$(mktemp -d)"
proj="$work/proj"
mkdir -p "$proj"
export TATTOO_DIR="$proj/.tattoos"
sid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
tattoo="$TATTOO_DIR/$sid.md"
# cc PROMPT [claude flags...]. The prompt goes through stdin: --allowedTools and
# --disallowedTools are variadic and would swallow a positional prompt.
cc() {
  local prompt="$1"; shift
  (cd "$proj" && printf '%s' "$prompt" | claude -p --model "$model" --plugin-dir "$root" "$@")
}

pass=0
fail=0
check() {
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; fi
}

echo "session $sid, work dir $work"

cc "We are planning a toy project called Otter. Decision: we use SQLite, not Postgres, because I said 'no servers'. The start codeword is BLUE-HERON. Reply with just OK." --session-id "$sid" >/dev/null

cc "/tattoo:tattoo" --resume "$sid" --allowedTools Bash Read Write Edit >"$work/tattoo-reply.txt"
check "skill wrote the tattoo" test -s "$tattoo"
check "tattoo keeps the decision" grep -qi 'sqlite' "$tattoo"
check "tattoo keeps the codeword" grep -q 'BLUE-HERON' "$tattoo"
cp "$tattoo" "$work/tattoo-as-written.md" 2>/dev/null

# Pad the tattoo past the 10,000-char hook-output cap, then put a codeword at the very end.
{
  printf '\n## Padding\n'
  for i in $(seq 1 400); do
    printf 'Line %03d: filler text that stands in for a long, detailed session log entry.\n' "$i"
  done
  printf '\nEnd codeword: SILVER-FOX.\n'
} >>"$tattoo"
echo "tattoo size: $(wc -c <"$tattoo" | tr -d ' ') bytes"

cc "/compact" --resume "$sid" >"$work/compact-reply.txt"

cc "Without using tools: what is the start codeword and what is the end codeword in your session tattoo? Which database did we pick? Answer in one line." \
  --resume "$sid" --disallowedTools Bash Read Write Edit Glob Grep >"$work/answer.txt"
echo "answer: $(cat "$work/answer.txt")"

transcript="$(ls -t "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -n 1)"
check "transcript found" test -n "$transcript"
check "hook output in transcript" grep -q 'Session tattoo written' "$transcript"
parts_seen() { # prints "<parts injected verbatim> <parts persisted>"
  python3 - "$1" <<'PY'
import json, sys
ok = persisted = 0
for line in open(sys.argv[1]):
    if '"attachment"' not in line or "[tattoo]" not in line:
        continue
    att = json.loads(line).get("attachment", {})
    content = att.get("content")
    text = content if isinstance(content, str) else json.dumps(content)
    if "[tattoo]" not in (att.get("stdout") or text):
        continue
    if "<persisted-output>" in text:
        persisted += 1
    elif "--- end of tattoo" in text:
        ok += 1
print(ok, persisted)
PY
}
seen="$(parts_seen "$transcript")"
echo "tattoo parts in context: ${seen% *} verbatim, ${seen#* } persisted"
check "several parts, all verbatim" test "${seen% *}" -gt 1 -a "${seen#* }" = 0
check "answer: start codeword" grep -q 'BLUE-HERON' "$work/answer.txt"
check "answer: end codeword" grep -q 'SILVER-FOX' "$work/answer.txt"
check "answer: decision" grep -qi 'sqlite' "$work/answer.txt"

echo
echo "passed $pass, failed $fail  (artifacts: $work, transcript: ${transcript:-none})"
[ "$fail" = 0 ]
