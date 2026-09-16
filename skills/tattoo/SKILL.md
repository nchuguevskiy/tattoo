---
name: tattoo
description: Tattoo the session's knowledge into a file before /compact (history, forks and decisions, problems, project knowledge, user rules, open items). Right after compaction a SessionStart hook reads it back into context verbatim.
argument-hint: "[what to focus on next]"
disable-model-invocation: true
allowed-tools: Bash(bash *where.sh*) Read(~/.local/state/tattoo/**) Edit(~/.local/state/tattoo/**) Write(~/.local/state/tattoo/**)
---

Snapshot of this session before compaction. You write it while the context is
still whole; right after `/compact` (manual or auto) the tattoo hook prints the
file back into context verbatim. The compaction summary drops forks and reasons.
The tattoo keeps them.

## Where

Tattoo file: !`bash "${CLAUDE_SKILL_DIR}/scripts/where.sh" "${CLAUDE_SESSION_ID}"`

Write the tattoo to exactly that path, replacing the whole file. If the line
says "exists", Read the file first and carry over everything still true: the
new tattoo replaces the old one entirely. If the line shows a command instead
of a path, run the command yourself.

## Style

Terse: no filler, no preambles, no pleasantries; fragments are fine. Keep facts,
numbers, paths, commands, hashes and names verbatim. Write in the user's
language. Completeness beats brevity: a lost fork costs more than an extra line.

## Sections

1. `# Tattoo · <project> · <date time> · branch <name>` plus one line on what the
   session is about.
2. `## History`: the whole session in order, not just the end. For each step:
   task, what was done, outcome (commit, branch, merged / pushed / not).
3. `## Forks and decisions`: the question, the options, who chose (the user as
   a quote, Claude with its reason), what was rejected and why.
4. `## Problems`: symptom, cause, fix. Dead ends: what did not work and why.
5. `## Knowledge`: what to run and how, where things live, architecture,
   contracts, environment, access (no secrets), gotchas. For anything already
   recorded in the repo or in memory, give the path instead of retelling it.
6. `## User rules`: standing and one-off bans, permissions, how to answer, what
   to do only when the user says so.
7. `## Open`: questions to the user verbatim, what awaits a decision, the next
   step, background tasks.
8. `## Where the details are`: the transcript path and search markers for
   primary data that cannot be reproduced (user pastes, answers from people,
   output from other environments); files handed over (path, sha).

## Do not write

Command and test output, contents of files you read, diffs, code, line-by-line
edits. For a measurement, write the number, the dataset and the date, not the
log. For a file, give the path and its role in one line. Never write secrets,
tokens or passwords.

## Argument

If the user gave one, it is the focus of the next stage: expand that part in
more detail and cut nothing else.

## Finish

One line to the user: the path, the size, and "now run `/compact`".
