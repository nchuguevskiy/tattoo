# tattoo

<p align="center">
  <img src="assets/hero.png" width="820" alt="Three Polaroid-style photos of terminal screens, Memento-style, with handwritten notes: 'Postgres. NOT Redis. Don't trust the summary. Read your tattoo.', 'never push to main', 'FOR UPDATE = dead end'.">
</p>

**Claude forgets on every `/compact`. Tattoo what matters first.**

[Русская версия](README.ru.md)

In *Memento*, Leonard's memory resets every few minutes. He gets by with
tattoos and Polaroids: before the reset he writes down what matters, and after
it he reads what he wrote.

Claude Code has the same condition. When the context fills up, `/compact` (or
auto-compact) replaces the conversation with a summary. The summary keeps
*what* happened and loses *why*: the options you rejected and the reasons, the
rule you set two hours ago, the dead end you already walked. After compaction,
Claude proposes the approach you rejected an hour ago.

`tattoo` fixes this with three small parts:

1. **`/tattoo`**: a skill that makes Claude write a structured snapshot of the
   session to `~/.local/state/tattoo/<session-id>.md` *while the context is
   still whole*.
2. **A `SessionStart` hook with matcher `compact`**: right after every
   compaction, manual or auto, it puts that file back into context verbatim.
3. **Compact instructions** (optional): a `CLAUDE.md` block that makes the
   compaction summary itself keep forks and decisions, and not duplicate the
   tattoo.

No MCP server, no database, no daemon: one Markdown file per session and two
small bash scripts.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/how-it-works-dark.svg">
  <img src="assets/how-it-works-light.svg" width="960" alt="Diagram: while the context is still whole, /tattoo writes decisions, forks, user rules, dead ends and open questions to ~/.local/state/tattoo/&lt;session&gt;.md. After /compact, manual or auto, the file comes back as parts 1/5 to 5/5 through the SessionStart:compact hook, 8 hook copies of at most 10k characters each, verbatim. Compaction summary plus the parts make up Claude's context.">
</picture>

## Demo

<p align="center">
  <img src="assets/demo.gif" width="900" alt="Terminal recording: a resumed Claude Code session runs /tattoo, then /compact, then answers 'Where do we keep idempotency keys, and what did we rule out?' with Postgres, Redis ruled out, and 'Can I push this to main?' with 'No, draft PRs only'.">
</p>

A real session with the plugin loaded, recorded with [vhs](https://github.com/charmbracelet/vhs)
(`assets/demo.tape`). The waits for writing the tattoo and for compaction are cut.

## What a tattoo looks like

```markdown
# Tattoo · billing-api · 2026-09-14 16:20 · branch feat/idempotency
Adding idempotency keys to POST /charges; client retries were double-charging.

## History
1. Reproduced the double charge: retry after a 504 gives two rows in `charges`. Staging.
2. `idempotency_keys` table + middleware: commit a1c9e02, pushed, draft PR #412.
3. Load test: p99 +3 ms (k6, 500 rps, staging, 2026-09-14).

## Forks and decisions
- Key storage: Redis or Postgres. User: "no new infra, Postgres". Redis rejected; TTL was its only upside.
- Key scope: per account, not global. Claude: avoids cross-tenant collisions.
- Rejected: request-body hash as the key; it breaks legitimate repeats with the same payload.

## Problems
- Middleware ran after the body parser, key was undefined. Fix: mounted before `express.json()`.
- Dead end: `SELECT ... FOR UPDATE` deadlocked under k6. Replaced with `INSERT ... ON CONFLICT DO NOTHING`.

## Knowledge
- Integration tests: `pnpm test:int` (needs `docker compose up db`).
- Migrations live in `db/migrations/`, run with `pnpm migrate`.

## User rules
- Never push to main; PRs as drafts only.
- Do not touch `legacy/` without asking.

## Open
- Asked the user: "Key TTL: 24h or 7d?" No answer yet.
- Next: a job that expires old keys.

## Where the details are
- Transcript: ~/.claude/projects/-home-me-billing-api/5f0c….jsonl, search "504 retry".
```

## Install

### Option A: plugin (recommended)

Inside Claude Code:

```text
/plugin marketplace add nchuguevskiy/tattoo
/plugin install tattoo@tattoo
```

Or from a shell:

```bash
claude plugin marketplace add nchuguevskiy/tattoo
claude plugin install tattoo@tattoo
```

Restart Claude Code. The skill shows up as `/tattoo` (full name
`/tattoo:tattoo`), and the plugin registers the hook.

### Option B: manual install, no plugin system

```bash
git clone https://github.com/nchuguevskiy/tattoo.git
cd tattoo
./install.sh                          # English skill
./install.sh --lang ru                # Russian skill
./install.sh --compact-instructions   # also append Compact instructions to ~/.claude/CLAUDE.md
```

This copies the skill to `~/.claude/skills/tattoo/` and the hook to
`~/.claude/hooks/tattoo-restore.sh`, and adds a `SessionStart` hook group with
matcher `compact` to `~/.claude/settings.json`. Existing settings are kept, a
backup is saved next to the file, and running the script twice is safe.
`CLAUDE_CONFIG_DIR` is respected.

### Step 3 (recommended): Compact instructions

A plugin cannot edit your `CLAUDE.md`, so add the block yourself.
[Claude Code reads a `# Compact instructions` section](https://code.claude.com/docs/en/costs#manage-context-proactively)
from `CLAUDE.md` when it compacts:

```bash
curl -fsSL https://raw.githubusercontent.com/nchuguevskiy/tattoo/main/templates/compact-instructions.md >> ~/.claude/CLAUDE.md
```

Russian version: `i18n/ru/compact-instructions.md`. With option B, the
`--compact-instructions` flag does the same thing.

### Check it

- `/hooks` lists eight `SessionStart` hooks with matcher `compact` (see
  [Big tattoos](#big-tattoos) for why there are eight).
- Run `/tattoo`, then `/compact`, then ask Claude "what does your tattoo say
  about our decisions?"

Requirements: Claude Code with plugins and hooks, `bash`, and `jq` or
`python3` (the hook falls back to `sed` when neither is present). Tested on
macOS; should work on Linux; on Windows, use WSL or Git Bash (not tested).

## Usage

```text
/tattoo                              snapshot the session
/tattoo next: the payments migration   same, with a focus for the next stage
/compact
```

- **When to run it:** at around 60–80% context, before switching to a new phase
  of the work, or whenever a lot has been decided. Auto-compact also triggers
  the hook, so it restores the most recent tattoo, whenever you wrote it.
- **Tattoos grow across compactions.** A new `/tattoo` reads the old one first
  and carries over whatever is still true, so after three compactions it still
  covers the whole session. A third compaction summary, by contrast, is a
  summary of a summary of a summary.
- **One tattoo per session.** `/clear` starts a new session, which has no
  tattoo. `--resume` keeps the session id, so the tattoo still applies.
- **The hook prints the tattoo's age.** Anything that happened after the tattoo exists
  only in the summary, and the hook tells Claude to trust the summary where
  the two disagree.

## Big tattoos

Claude Code replaces any single hook output longer than 10,000 characters with
a 2 KB preview and a file path. The limit applies to each hook separately and
cannot be configured (measured on Claude Code 2.1.273). A detailed tattoo is
often 20–60 KB, so a single hook would deliver only its first 2 KB.

This is not hypothetical. In two real sessions with the pre-release version,
which used a single hook, all 13 compactions hit the limit (snapshots of
13,000–62,000 characters). Claude read the full file as its first step after
only 6 of them; after the others it worked from the 2 KB preview for dozens to
hundreds of tool calls.

To get around this, tattoo registers eight copies of the hook. Each copy prints
one part of the tattoo: at most 8,500 characters, cut at line boundaries and
labelled `part i/N`. Together they deliver up to about 68,000 characters
(about 17k tokens of English text) verbatim. The copies run in parallel, so parts can arrive
out of order; the first part tells Claude to read them in part order.

- If a tattoo needs more than eight parts, the first part tells Claude to Read
  the rest of the file from a given line before continuing.
- If a future Claude Code version changes the limit and a part arrives as
  "Output too large", the same header tells Claude to Read the whole file.
- `tests/e2e.sh` checks this end to end: it compacts a session with a 32 KB
  tattoo and asks Claude, with tools disabled, for a codeword from the last
  line.

`TATTOO_PART_SIZE` (default `8500`) sets the part size.

## Configuration

| Variable     | Default                   | Purpose |
|--------------|---------------------------|---------|
| `TATTOO_DIR` | `$XDG_STATE_HOME/tattoo`, or `~/.local/state/tattoo` | Where tattoos are stored. Set it in your shell or in the `env` block of `settings.json`, so the hook and the skill both see it. |
| `TATTOO_PART_SIZE` | `8500` | Maximum characters per hook part. Keep it below 10,000 minus about 1,000 for the header. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Where `install.sh` puts the skill, the hook and the settings entry. |

**Why not `~/.claude/tattoos`?** Claude Code treats `.claude` as a
[protected path](https://code.claude.com/docs/en/permission-modes#protected-paths):
every write there asks for confirmation, and allow rules cannot pre-approve it.
The skill pre-approves writes to `~/.local/state/tattoo/`, so `/tattoo` runs
without prompts. If you point `TATTOO_DIR` somewhere else, Claude will ask
before writing there unless you add an allow rule such as
`Edit(//path/to/tattoos/**)` to your settings.

## FAQ

**Why not just `/compact focus on X`, or only Compact instructions?**
The summary is written at compaction time by a model under pressure to be
short, and it is rewritten at every compaction. A tattoo is written on
purpose, beforehand, from the full context, and it returns word for word. Use
both: Compact instructions make the summary better, and the tattoo keeps what
the summary still drops.

**Why not `CLAUDE.md` or memory?**
They hold facts that should outlive the session. A tattoo holds the working
state of *this* session: the fork you are at, the question you are waiting on,
the dead end from an hour ago. When something is already in `CLAUDE.md` or in
memory, the tattoo refers to it by path instead of copying it.

**Claude Code already re-reads some files after compaction. Why the hook?**
Right after `/tattoo` and `/compact` you may see Claude Code re-attach the
tattoo on its own (`Read …/tattoo/<session>.md`, as in the demo), because it is
one of the files the session touched last. That is a convenience, not a
guarantee: it covers recently used files, so an auto-compact an hour after the
tattoo, after dozens of other files, may leave it out. The hook runs after every
compaction and returns the whole file, split into parts when needed.

**Why not write it automatically in a `PreCompact` hook?**
A `PreCompact` hook cannot add context or block compaction, and a shell script
cannot write a good summary of a conversation it cannot see. A good tattoo
needs the model and the whole context, so writing one is a command you run.

**What about secrets?**
The skill tells Claude never to write secrets, tokens or passwords. Tattoos are
plain files in your home directory; delete them with `rm -rf ~/.local/state/tattoo`.
The hook only reads a file whose name is the session id, and it ignores any id
that is not made of letters, digits and dashes.

**How do I see what Claude got back?**
The hook output is stored in the session transcript
(`~/.claude/projects/<project>/<session-id>.jsonl`) as an attachment right after
the compaction.

## Development

```bash
tests/test.sh      # offline: parsing fallbacks, splitting (awk, gawk, mawk), install/uninstall on a throwaway HOME
tests/e2e.sh       # real Claude Code (haiku): /tattoo, /compact, recall; spends a few cents
claude plugin validate .
assets/build.sh    # re-render assets/hero.png and assets/social-preview.png (headless Chrome)
assets/demo-setup.sh && assets/demo-setup.sh --render && assets/demo-setup.sh --cleanup   # re-record assets/demo.gif (vhs, real Claude Code)
```

## Uninstall

- Plugin: `/plugin uninstall tattoo@tattoo`, then optionally
  `/plugin marketplace remove tattoo`.
- Manual install: `./uninstall.sh`.

Tattoos stay in `~/.local/state/tattoo` until you delete them. If you added
Compact instructions to `CLAUDE.md`, remove that block by hand.

## Credits

The idea comes from *Memento* (2000). The terse writing style is inspired by
[caveman](https://github.com/JuliusBrussee/caveman).

## License

MIT
