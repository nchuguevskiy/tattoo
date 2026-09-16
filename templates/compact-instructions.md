
# Compact instructions

The compaction summary is the project log, not a retelling of the session. The
main enemy is over-compression: a lost fork costs more than an extra line.
Terse style: no filler; keep facts, numbers, paths, commands and hashes verbatim.

Keep:
- the history in order, for the whole session: task, what was done, outcome
  (commit, branch, merged / pushed);
- forks: the question, the options, who chose (the user as a quote, Claude with
  its reason), what was rejected;
- problems: symptom, cause, fix; dead ends;
- knowledge: what to run, where things live, architecture, contracts,
  environment, gotchas; for anything recorded in the repo or memory, the path;
- the user's rules and bans, standing and one-off;
- open items: questions to the user verbatim, what awaits a decision, the next
  step, background tasks;
- the user's messages verbatim; logs and outputs they pasted, compressed to
  facts and marked "full text in transcript".

Drop: command and test output, contents of files read, diffs, code fragments,
line-by-line edits. In the files section, give each file's path and role in one
line. For a measurement, keep the number, the dataset and the date, not the log.

If there was a `/tattoo` (`~/.local/state/tattoo/<session_id>.md`), a hook brings it
back right after compaction. Do not duplicate it; record only what happened
after it.
