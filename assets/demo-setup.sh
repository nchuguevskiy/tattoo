#!/usr/bin/env bash
# Builds the terminal demo recorded by assets/demo.tape.
#
#   assets/demo-setup.sh            prepare /tmp and a pre-built Claude Code session
#   assets/demo-setup.sh --render   record assets/demo.tape and write assets/demo.gif
#   assets/demo-setup.sh --cleanup  remove the demo files from /tmp
#
# Needs: claude, vhs, ffmpeg, gifsicle (brew install vhs gifsicle).
#
# Uses a separate, logged-in config dir (DEMO_CONFIG_DIR, default ~/.claude-demo),
# so your own plugins, hooks and CLAUDE.md stay out of the demo. Log in once with
#   CLAUDE_CONFIG_DIR=~/.claude-demo claude auth login
# The first run merges three things into that dir's .claude.json (a backup goes
# to .claude.json.bak-demo): onboarding done, dark theme, /tmp/billing-api trusted.
#
# Creates:
#   /tmp/billing-api          tiny fake repo, the project the demo session runs in
#   /tmp/tattoo               copy of this plugin, so no home path shows on screen
#   /tmp/demo-tattoo          TATTOO_DIR for the demo
#   /tmp/demo-settings.json   extra settings for the demo session (--settings): the
#                             allow rule the README asks for when TATTOO_DIR is not
#                             the default, model, no tips or prompt suggestions
#   /tmp/demo-env.sh          environment the tape sources (session id, config dir)
#   /tmp/demo-frames/         raw frames from vhs (--render)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${DEMO_CONFIG_DIR:-$HOME/.claude-demo}"
model="${DEMO_MODEL:-sonnet}"
proj=/tmp/billing-api
plugin=/tmp/tattoo
tattoos=/tmp/demo-tattoo
settings=/tmp/demo-settings.json
envfile=/tmp/demo-env.sh
frames=/tmp/demo-frames

# A clean environment: nothing from a parent Claude Code session.
for v in $(env | sed -n -E 's/^(CLAUDECODE|CLAUDE_CODE_[A-Z_]*|CLAUDE_JOB_DIR|CLAUDE_PID|CLAUDE_EFFORT)=.*/\1/p'); do
  unset "$v"
done
# No auto memory: it would add memory chatter (and a config path) to the session.
export CLAUDE_CONFIG_DIR="$config" TATTOO_DIR="$tattoos" DISABLE_AUTOUPDATER=1 \
  CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

case "${1:-}" in
  --cleanup)
    rm -rf "$proj" "$plugin" "$tattoos" "$settings" "$envfile" "$frames"
    exit 0 ;;
  --render)
    [ -s "$envfile" ] || { echo "run $0 first" >&2; exit 1; }
    rm -rf "$frames"
    (cd "$root" && vhs assets/demo.tape)
    # vhs writes frames; assemble them here (text + cursor layers, centered on a
    # 1200x700 GitHub Dark canvas, one shared palette), then shrink.
    fps=20
    ffmpeg -v error -y -framerate "$fps" -i "$frames/frame-text-%05d.png" \
      -framerate "$fps" -i "$frames/frame-cursor-%05d.png" \
      -filter_complex "[0][1]overlay,pad=1200:700:(ow-iw)/2:(oh-ih)/2:color=0x101216,split[a][b];[a]palettegen=max_colors=64:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
      -loop 0 "$frames/raw.gif"
    gifsicle -O3 --lossy=40 "$frames/raw.gif" -o "$root/assets/demo.gif"
    ls -l "$root/assets/demo.gif"
    exit 0 ;;
esac

[ -d "$config" ] || { echo "no config dir $config; log in first (see the header)" >&2; exit 1; }

python3 - "$config/.claude.json" "$proj" <<'PY'
import json, os, shutil, sys
path, proj = sys.argv[1:]
data = {}
if os.path.exists(path):
    if not os.path.exists(path + ".bak-demo"):
        shutil.copy2(path, path + ".bak-demo")
    with open(path) as f:
        data = json.load(f)
data["hasCompletedOnboarding"] = True
data["theme"] = "dark"
for p in (proj, "/private" + proj):
    data.setdefault("projects", {}).setdefault(p, {})["hasTrustDialogAccepted"] = True
with open(path + ".tmp-demo", "w") as f:
    json.dump(data, f, indent=2)
os.chmod(path + ".tmp-demo", 0o600)
os.replace(path + ".tmp-demo", path)
PY

rm -rf "$proj" "$plugin" "$tattoos"
mkdir -p "$proj" "$tattoos" "$plugin"

cat > "$settings" <<EOF
{
  "model": "$model",
  "permissions": {
    "allow": ["Read(/$tattoos/**)", "Edit(/$tattoos/**)", "Read(//private$tattoos/**)", "Edit(//private$tattoos/**)"]
  },
  "autoMemoryEnabled": false,
  "promptSuggestionEnabled": false,
  "spinnerTipsEnabled": false
}
EOF

# The plugin, minus git data and assets.
(cd "$root" && tar --exclude .git --exclude assets -cf - .) | (cd "$plugin" && tar -xf -)

# A tiny fake project.
(
  cd "$proj"
  git init -q -b main
  printf '# billing-api\n\nCharges and refunds service.\n' > README.md
  git add README.md
  git -c user.name=demo -c user.email=demo@example.com commit -qm "init"
  git checkout -q -b feat/idempotency
)

sid="$(uuidgen | tr '[:upper:]' '[:lower:]')"

# say PROMPT [claude flags...]: one headless turn, no tools, short reply.
say() {
  local prompt="$1"; shift
  (cd "$proj" && printf '%s' "$prompt" | claude -p --model "$model" --tools "" \
    --append-system-prompt "This is a planning chat: reply in one short sentence, do not use tools." "$@")
}

say "We're adding idempotency keys to POST /charges: client retries after a 504 were double-charging." --session-id "$sid"
say "Where do the keys live, Redis or Postgres? Postgres. No new infra, so Redis is out." --resume "$sid"
say "Rule for this repo: never push to main, PRs as drafts only." --resume "$sid"
say "Key scope: per account, not global, so tenants never collide." --resume "$sid"
say "Integration tests: pnpm test:int (needs docker compose up db)." --resume "$sid"
say "Dead end: SELECT ... FOR UPDATE deadlocked under k6 at 500 rps. Replaced it with INSERT ... ON CONFLICT DO NOTHING, no deadlocks since." --resume "$sid"
say "Still open: key TTL, 24h or 7d? Don't decide yet." --resume "$sid"

cat > "$envfile" <<EOF
export CLAUDE_CONFIG_DIR='$config'
export TATTOO_DIR='$tattoos'
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export SID='$sid'
export PS1='\$ '
claude() { command claude --settings $settings --no-chrome "\$@"; }
EOF
echo "session $sid"
