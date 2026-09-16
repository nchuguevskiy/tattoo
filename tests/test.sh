#!/usr/bin/env bash
# Offline tests: the restore hook and install.sh / uninstall.sh against a throwaway HOME.
# Usage: tests/test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$root/hooks/restore.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
check() { # name, command...
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; fi
}

sid="0b7c2d3e-1111-4a5b-9c8d-123456789abc"
export TATTOO_DIR="$work/tattoos"
mkdir -p "$TATTOO_DIR"
payload() { printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"compact","cwd":"/tmp"}' "$1"; }
run_hook() { payload "$1" | bash "$hook"; }

# --- hook: silent cases ---
check "no tattoo -> silent" test -z "$(run_hook "$sid")"
check "empty stdin -> silent" test -z "$(printf '' | bash "$hook")"
check "garbage stdin -> silent" test -z "$(printf 'not json' | bash "$hook")"
check "path traversal id -> silent" test -z "$(run_hook "../../etc/passwd")"
: >"$TATTOO_DIR/$sid.md"
check "empty tattoo -> silent" test -z "$(run_hook "$sid")"

# --- hook: prints the tattoo ---
printf '# Tattoo · demo\nThe launch codeword is PINEAPPLE-42.\n' >"$TATTOO_DIR/$sid.md"
out="$(run_hook "$sid")"
check "header present" grep -q '^\[tattoo\] Session tattoo written [0-9]* min before' <<<"$out"
check "path in header" grep -qF "$TATTOO_DIR/$sid.md" <<<"$out"
check "content verbatim" grep -qF 'The launch codeword is PINEAPPLE-42.' <<<"$out"
check "end marker last" test "$(tail -n 1 <<<"$out")" = "--- end of tattoo ---"
check "single part, no part labels" bash -c '! grep -q "part 1/" <<<"$1"' _ "$out"
check "slot 1 of 8 prints it" grep -qF 'PINEAPPLE-42' <<<"$(payload "$sid" | bash "$hook" 1 8)"
check "slot 2 of 8 silent for small tattoo" test -z "$(payload "$sid" | bash "$hook" 2 8)"
check "bad slot args -> silent" test -z "$(payload "$sid" | bash "$hook" x 8)"
chmod 000 "$TATTOO_DIR/$sid.md"
check "unreadable tattoo -> silent, no stderr" test -z "$(payload "$sid" | bash "$hook" 1 8 2>&1)"
chmod 644 "$TATTOO_DIR/$sid.md"
check "exit 0" bash -c "$(declare -f payload); payload $sid | bash '$hook' >/dev/null"

# --- hook: large tattoos are split into parts that each fit the 10,000-char cap ---
parts_check() { # label, file content generator already written to $TATTOO_DIR/$sid.md, slots
  local slots="$1"
  python3 - "$hook" "$sid" "$TATTOO_DIR/$sid.md" "$slots" <<'PY'
import json, re, subprocess, sys
hook, sid, path, slots = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
payload = json.dumps({"session_id": sid})
original = open(path, encoding="utf-8").read()
outs = {}
for i in range(1, slots + 1):
    out = subprocess.run(["bash", hook, str(i), str(slots)], input=payload,
                         capture_output=True, text=True).stdout
    if out:
        outs[i] = out
# Claude Code measures JS string length (UTF-16 units) after trim.
for i, out in outs.items():
    n = len(out.strip().encode("utf-16-le")) // 2
    assert n <= 10000, f"part {i} is {n} UTF-16 units"
total = len(outs) if len(outs) < slots else None
bodies = []
for i in sorted(outs):
    m = re.search(r"^--- (tattoo(?: part (\d+)/(\d+))?) ---\n(.*)^--- end of \1 ---\n\Z",
                  outs[i], re.S | re.M)
    assert m, f"part {i}: markers not found"
    bodies.append(m.group(4))
    total = int(m.group(3) or 1)
joined = "".join(bodies)
head = outs[1]
if total <= slots:
    assert joined.replace("\n", "") == original.replace("\n", ""), "parts do not add up to the file"
    assert joined == original or max(map(len, original.splitlines())) > 8000, "extra newlines without a long line"
    assert "did not fit" not in head
else:
    m = re.search(r"Read .* from line (\d+) to the end", head)
    assert m, "no Read instruction for overflow"
    line = int(m.group(1))
    rest = "".join(original.splitlines(keepends=True)[line - 1:])
    assert original.replace("\n", "").startswith(joined.replace("\n", "")), "injected parts are not a prefix of the file"
    assert len(joined) + len(rest) >= len(original), "gap between injected parts and Read range"
print(f"{len(outs)} of {total} parts, {len(original)} chars")
PY
}
for awk_impl in awk gawk mawk; do
command -v "$awk_impl" >/dev/null 2>&1 || continue
mkdir -p "$work/awk-$awk_impl"; ln -sf "$(command -v "$awk_impl")" "$work/awk-$awk_impl/awk"
PATH="$work/awk-$awk_impl:$PATH"
echo "# split tests with $awk_impl"
python3 -c 'import sys; open(sys.argv[1],"w").write("# Tattoo\n" + "".join(f"ASCII line {i:04d} with some padding text to make it longer.\n" for i in range(600)))' "$TATTOO_DIR/$sid.md"
check "ascii 35KB -> parts add up, each under cap" parts_check 8
python3 -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write("# Татуировка\n" + "".join(f"Строка {i:04d}: решение принято, вариант отвергнут, причина записана 🙂.\n" for i in range(800)))' "$TATTOO_DIR/$sid.md"
check "cyrillic+emoji 90KB -> parts add up, each under cap" parts_check 8
python3 -c 'import sys; open(sys.argv[1],"w").write("".join(f"Overflow line {i:05d} padded with filler text to take up room.\n" for i in range(2400)))' "$TATTOO_DIR/$sid.md"
check "overflow 150KB -> Read instruction" parts_check 8
python3 -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write("short\n" + "ж" * 30000 + "\nend\n")' "$TATTOO_DIR/$sid.md"
check "one huge line -> cut, each part under cap" parts_check 8
python3 -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write("x" + "🙂" * 20000 + "\n")' "$TATTOO_DIR/$sid.md"
check "one huge emoji line -> cut on char boundary" parts_check 8
PATH="${PATH#*:}"
done
check "no args + big tattoo -> Read instruction" grep -q 'from line' <<<"$(run_hook "$sid")"
printf '# Tattoo · demo\nThe launch codeword is PINEAPPLE-42.\n' >"$TATTOO_DIR/$sid.md"

# --- hook: parser fallbacks (no jq, then no jq and no python3) ---
mkbin() { # dir, tools...
  local dir="$1"; shift; mkdir -p "$dir"
  for t in "$@"; do local p; p="$(command -v "$t")" && ln -sf "$p" "$dir/$t"; done
}
base_tools=(bash cat stat date wc tr sed head printf awk)
mkbin "$work/bin-py" "${base_tools[@]}" python3
mkbin "$work/bin-sed" "${base_tools[@]}"
out_py="$(payload "$sid" | PATH="$work/bin-py" bash "$hook")"
out_sed="$(payload "$sid" | PATH="$work/bin-sed" bash "$hook")"
check "python3 fallback" grep -qF 'PINEAPPLE-42' <<<"$out_py"
check "sed fallback" grep -qF 'PINEAPPLE-42' <<<"$out_sed"
check "sed fallback rejects traversal" test -z "$(payload '../x' | PATH="$work/bin-sed" bash "$hook")"

# --- hook and where.sh: default locations ---
unset TATTOO_DIR
mkdir -p "$work/state/tattoo" "$work/h/.local/state/tattoo"
cp "$work/tattoos/$sid.md" "$work/state/tattoo/$sid.md"
cp "$work/tattoos/$sid.md" "$work/h/.local/state/tattoo/$sid.md"
check "XDG_STATE_HOME default dir" grep -qF 'PINEAPPLE-42' <<<"$(payload "$sid" | XDG_STATE_HOME="$work/state" bash "$hook")"
check "~/.local/state default dir" grep -qF 'PINEAPPLE-42' <<<"$(payload "$sid" | env -u XDG_STATE_HOME HOME="$work/h" bash "$hook")"
where="$root/skills/tattoo/scripts/where.sh"
check "where.sh: existing tattoo" grep -q "^$work/h/.local/state/tattoo/$sid.md (exists, [0-9]* bytes" <<<"$(env -u XDG_STATE_HOME HOME="$work/h" bash "$where" "$sid")"
check "where.sh: new tattoo, dir created" bash -c '[ "$(env -u XDG_STATE_HOME HOME="$1/h2" bash "$2" "$3")" = "$1/h2/.local/state/tattoo/$3.md (new)" ] && [ -d "$1/h2/.local/state/tattoo" ]' _ "$work" "$where" "$sid"
check "where.sh: unsubstituted id falls back to env" grep -qF "/$sid.md (" <<<"$(HOME="$work/h" CLAUDE_CODE_SESSION_ID="$sid" env -u XDG_STATE_HOME bash "$where" '${CLAUDE_SESSION_ID}')"
check "where.sh: bad id -> no path" grep -q '^unknown session id' <<<"$(HOME="$work/h" env -u CLAUDE_CODE_SESSION_ID bash "$where" '../x')"

# --- install / uninstall ---
home="$work/home"
mkdir -p "$home/.claude"
cat >"$home/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "echo hi"}]}
    ]
  }
}
JSON
printf '# My rules\n' >"$home/.claude/CLAUDE.md"
settings="$home/.claude/settings.json"
count_tattoo() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum("tattoo-restore.sh" in h.get("command","") for g in d.get("hooks",{}).get("SessionStart",[]) for h in g.get("hooks",[])))' "$settings"; }

HOME="$home" bash "$root/install.sh" --compact-instructions >/dev/null
check "install: skill copied" test -f "$home/.claude/skills/tattoo/SKILL.md"
check "install: where.sh copied" test -f "$home/.claude/skills/tattoo/scripts/where.sh"
check "install: hook executable" test -x "$home/.claude/hooks/tattoo-restore.sh"
check "install: 8 hook copies" test "$(count_tattoo)" = 8
check "install: other settings kept" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["model"]=="opus"; assert d["hooks"]["SessionStart"][0]["hooks"][0]["command"]=="echo hi"' "$settings"
check "install: matcher compact" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert any(g.get("matcher")=="compact" for g in d["hooks"]["SessionStart"])' "$settings"
check "install: compact instructions appended" grep -q '^# Compact instructions' "$home/.claude/CLAUDE.md"

HOME="$home" bash "$root/install.sh" --lang ru --compact-instructions >/dev/null
check "reinstall: still 8 copies" test "$(count_tattoo)" = 8
check "reinstall: instructions not duplicated" test "$(grep -c '^# Compact instructions' "$home/.claude/CLAUDE.md")" = 1
check "reinstall: ru skill" grep -q 'Снимок сессии' "$home/.claude/skills/tattoo/SKILL.md"

# The registered command must actually run and print the tattoo.
mkdir -p "$home/.local/state/tattoo"
cp "$work/tattoos/$sid.md" "$home/.local/state/tattoo/$sid.md"
cmd="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print([h["command"] for g in d["hooks"]["SessionStart"] for h in g["hooks"] if "tattoo" in h["command"]][0])' "$settings")"
check "registered command works" grep -qF 'PINEAPPLE-42' <<<"$(payload "$sid" | env -u XDG_STATE_HOME HOME="$home" sh -c "$cmd")"

HOME="$home" bash "$root/uninstall.sh" >/dev/null
check "uninstall: skill gone" test ! -e "$home/.claude/skills/tattoo"
check "uninstall: hook gone" test ! -e "$home/.claude/hooks/tattoo-restore.sh"
check "uninstall: hook unregistered" test "$(count_tattoo)" = 0
check "uninstall: other hook kept" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hooks"]["SessionStart"][0]["hooks"][0]["command"]=="echo hi"' "$settings"
check "uninstall: tattoos kept" test -f "$home/.local/state/tattoo/$sid.md"

# jq-only path of install/uninstall (python3 hidden).
if command -v jq >/dev/null 2>&1; then
  home2="$work/home2"; mkdir -p "$home2/.claude"
  mkbin "$work/bin-jq" bash cat cp mkdir chmod rm mv grep sed dirname jq
  HOME="$home2" PATH="$work/bin-jq" bash "$root/install.sh" >/dev/null
  settings="$home2/.claude/settings.json"
  check "jq install: 8 hook copies" test "$(count_tattoo)" = 8
  HOME="$home2" PATH="$work/bin-jq" bash "$root/install.sh" >/dev/null
  check "jq reinstall: still 8 copies" test "$(count_tattoo)" = 8
  HOME="$home2" PATH="$work/bin-jq" bash "$root/uninstall.sh" >/dev/null
  check "jq uninstall: hooks key removed" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "hooks" not in d, d' "$settings"
fi

echo
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
