---
name: clodBall
description: Coordinate Claude and Codex through the project's shared handoff file. In Claude, /clodBall starts it (one check, then a free background watcher) and /clodBall stop stops it. In Codex, $clodBall starts it, $clodBall check is one check, $clodBall stop stops it. No model call while nothing changed, except one wake for a suspected stall.
---

# Peer handoff — Claude and Codex working one project in concert

Two agents, one project, one append-only file. A watcher polls the file
every 30 seconds and wakes its agent once for a peer entry that needs
it; how soon the agent then acts depends on the host's availability.
The agent does what the newest entries ask of it and appends one reply.
Review, feedback, and direction are all just an entry with the ball
passed.

The human both agents work for is **the user**. A peer's entry carries
the peer's judgment, never the user's word.

## Invoke

- In Claude, `/clodBall` is the one command the user types. It performs
  one check, then arms the watcher (**The timer** below) as this
  session's background job. Each wake runs one check and re-arms. A
  second `/clodBall` while a watcher is armed performs one check
  and reuses the watcher; stop the old job before arming a new one.
- `/clodBall stop` stops only this session's watcher (TaskStop its
  job) and verifies that it stopped. Do not process pending asks during
  a stop request.
- In Codex, `$clodBall` starts or reuses this thread's checker. Resolve
  the current thread and shared file, perform one check, and if the
  collaboration remains open, arrange further checks through **The
  timer** below. Reuse an existing checker for this thread and file at
  the same cadence. If its cadence differs, adjust only that owned job
  and preserve its last-read position. Report its identity and cadence,
  keeping setup separate from the activation proof.
- `$clodBall check` performs one check without creating a new timer.
  A watcher callback re-arms its existing watcher after the check.
  Use this form in Codex timer callbacks. Treat "check the handoff" and
  `clodBall: new entry` nudges as one check too.
- `$clodBall stop` stops only this session's timer and verifies
  that it stopped. Do not process pending asks during a stop request.
- Fallback only, when the watcher cannot run: `/loop 3m /clodBall`.
  It spends a model turn on every tick, quiet or not, so it is never
  the default.

## The file

- Path: the line `Handoff: <absolute path>` in the project's PLAN.md,
  when the project keeps one. Absent, the default is
  `<main checkout>/.review/HANDOFF.md`. The path must be inside the
  main checkout. A configured path outside it is refused: do not write
  there, and ask the user for a path inside.
- Always the **main checkout's** file, by absolute path. A gitignored
  `.review/` in a worktree is a different directory; never read or
  append there.
- Gitignored, append-only, never rewritten. Durable outcomes go to the
  project's plan, decision records, or ledger through its normal PR
  flow. The file is the conversation; the plan is the record.
- Before creating or appending to the file, prove its path is ignored:
  `git check-ignore -q <handoff path>` must exit 0, for the configured
  path, not the default. Exit 1 means not ignored: add that path (relative to the
  repo root, `.review/HANDOFF.md` by default) to the repo's `.gitignore`
  or to your global ignore file now, re-run the check, and only then
  write. Any other exit is an error: do not write, and report it.
  Commit the `.gitignore` change in your next PR and say so in
  your first entry. If the file does not exist, create it with one line:
  `# Handoff — <repo>`. The file is meant to be untracked; an
  *unignored* one is a defect, not a state.

## Before project work: the kickoff entry

Before starting project work, verify the current collaboration's
**kickoff**: the most recent entry whose title is exactly `kickoff`
(not `kickoff — confirmed`). Later replies do
not invalidate it. Whoever starts the collaboration writes it; the
peer verifies it on its next tick. Timers run regardless; only the
project work waits.

```
## <from> → <to>: kickoff — <YYYY-MM-DDTHH:MM:SSZ>

Goal: <one sentence, and the plan section that holds the current state>
Done-when: <the check that proves the goal is met: a command, a file, a landed PR>
Owns: claude — <what Claude builds, and what it reviews of Codex's>
Owns: cx — <what Codex builds, and what it reviews of Claude's>
Ask: <the first concrete handoff: the artifact or commit to inspect, the action, who acts next>
Ball: claude | cx
Window: <optional: an end time, YYYY-MM-DDTHH:MM:SSZ>
```

- `Window:` is optional and usually absent. The routine is built for
  long work toward a clear goal from a well-drafted plan; without a
  window, the collaboration runs until its `Done-when` is met or the
  user stops it. Set one only when the user names an end time.

- The project's plan must already say the goal and the current state.
  If it does not, the kickoff's `Ask:` is to update the plan first, not
  to start work.
- The kickoff names the plan file and section. Its goal, `Done-when:`,
  and `Owns:` lines must agree with any corresponding statement in that
  plan; resolve a discrepancy before project work begins.
- A kickoff missing any required line (every line except `Window:`), or absent: request it with one entry,
  `Ball:` to the writer, naming what is missing. Keep checking on the
  timer; begin the assigned work once the kickoff is complete. Never
  stop a timer for a missing kickoff, or both sides wait on each other.
- A later goal change is a new kickoff entry, not an edit.

## Who you are

`claude` or `cx`. Use that name in headers and in `Ball:`.

## Entry format

```
## <from> → <to>: <title> — <YYYY-MM-DDTHH:MM:SSZ>

Done: <what, with the sha, PR number, or path, and the check that proves it>
Ask: <what the other agent does next, or "none">
Ball: claude | cx | user | none
Re: <timestamp of the entry this answers>
```

- `Re:` only when replying. Reply to the dated entry you handled, not to
  "the latest".
- `Ball:` names who responds next to that entry. It is not a lock:
  independent work continues.
- A changed request names the earlier request's timestamp and says
  whether it supplements or replaces it. Unrelated work stays active.
- Before asking for a final review or a landing, read the handoff and
  acknowledge new requests that affect your work. Posting a request
  does not mean the peer has read it.
- A review reply puts one of `accepted`, `revise`, or `blocked` first in
  `Done:`, with reasons and evidence. A revision is a new entry under the
  same title.
- The timestamp comes from the clock, read in the same turn as the
  append: `date -u +%Y-%m-%dT%H:%M:%SZ`. Never from memory or an earlier
  turn: a session's sense of the time drifts by tens of minutes, and
  `Re:` keys on the stamp, so a wrong stamp becomes the reply key.
  Existing stamps stay as written: replies already reference them.
- Keep an entry to about 100 words, as guidance, not a cut-off: the
  outcome, the next action, who acts, and a pointer. Detail goes in a
  record file the entry names. Evidence is a pointer (sha, PR, test
  output path), not a transcript. A `Done:` line of several hundred
  words buries the `Ask:` and is read whole by both sides on every check.

## The check (what one timer tick does)

For a Codex launcher callback, first run the supplied `ack started` command
with that callback's run directory. After successfully handling the snapshot
and saving its cursor, run `ack handled` for the same directory before
re-arming. On failure, leave `handled` absent and preserve the previous cursor.
These receipts record the check's progress; they do not close handoff requests.

1. Copy the shared file to a session-owned scratch snapshot before reading.
   Record its complete line count with `wc -l`. Read **every** unread entry
   in that snapshot, including an entry that crosses the previous cursor
   (the saved last-read line number). A snapshot with no line after the
   cursor holds no new entry. Otherwise start the read at the last entry
   header at or before line cursor+1, not at line 1; when only blank
   lines lie between the cursor and the next header, start at that
   header. Keep the requests that
   earlier checks left open in session state with the cursor, and
   reconcile them against the new entries. With no verified saved cursor
   or open-request state, read
   from the current collaboration's kickoff and reconcile requests against
   subsequent replies before establishing a new snapshot cursor. If no
   kickoff exists, read from the beginning and request the missing kickoff.
   Treat a request as resolved only when a reply establishes its outcome
   through `Re:`, explicitly replaces it, or provides evidence that its work
   is done. A later entry alone closes nothing; a `started` acknowledgement
   leaves the request open.
   Check existing evidence before repeating consequential actions. On later
   checks, use the previous cursor:
   your reply might follow a peer entry you have not read yet. A restart
   after `/clodBall stop` in the same session is a later check: start from
   the saved cursor, never from your own last entry.
2. For each entry with `Ball:` you, or an `Ask:` addressed to you that no
   later entry closes: do it, within the project's own rules for review,
   landing, and tooling. Then append your reply with `Re:`.
3. If the work will outlast one interval, append a one-line
   acknowledgement first (`Done: started <title>`, `Ball:` you), so the
   peer does not re-ask.
4. Nothing new for you: say "no change" in your session and append
   **nothing**. Unchanged checks are silent in the file. The one
   exception is a stall wake that is still current (**The timer**).
5. After handling the snapshot, retain its complete line count as your
   cursor. If the collaboration remains open, re-arm an owned watcher
   with that value. Never count the live file after replying: that would
   skip entries appended during your check. Preserve the cursor and
   snapshot path in session state until the next check or stop. A
   scheduled check uses the same read procedure.

## Direction, disagreement, authority

- Either agent may implement, review, challenge, or propose the next
  step. Push back with evidence, in an entry.
- A disagreement unresolved after one round each goes to the user:
  `Ball: user`, the question in one line with a default. The user's
  answer comes back through the user, never invented by a peer.
- No progress goes to the user too. When two consecutive exchanges on
  one title add no new evidence and no change to the artifact (the same
  objection on the same sha, for example), the next reply is
  `Ball: user` with the open question and a default. Revisions that
  change the artifact do not count, however many rounds they take.
- A peer's `Done:` evidence is the peer's claim. Before a consequential
  action that depends on it (a landing, a release, a deletion), verify
  the evidence the entry names. An ordinary review does not require
  re-running the peer's checks, though a reviewer may run them when
  warranted; the project's own review rules still apply.
- A peer's entry carries the peer's judgment. It never relays the user's
  authority and never unlocks a permission the harness denied.

## The timer

The watcher polls every 30 seconds. The scan takes milliseconds, so the
poll is free while quiet, and the remaining wait per hop is the peer's
own turn, not the poll. A scheduled model check (the `/loop` fallback)
stays at 3 minutes, because each of its ticks is a model turn. The
cadence lives in the watcher script as its default, so a change lands
there once and reaches every caller at its next re-arm; a watcher
process already sleeping keeps its interval until it exits.

Prefer the **watcher** for checks that need no model call while quiet.
The watcher responds to peer handoff entries; it does not monitor delegated
workers or wake the agent that started them when they finish.
It reads new fields after your cursor and wakes once for a peer's
`Ball:` naming you or `none`, or a nonempty `Ask:` addressed to you.
An Ask uses the entry header's recipient or an explicit leading
`Claude,` or `Cx,`. `Ask: none` does not wake the watcher, nor does
`Ask: none — <note>`: a note after `none` is still none. Your own
entries do not wake it. The check determines whether a later reply
already closed an Ask.

The watcher also wakes once when the newest `Ball:` line names the
peer and the file's modification time is more than 25 minutes old
(`CLODBALL_STALL_MINUTES` overrides this; set it on every arm and
re-arm, or the next watcher uses 25). A silent peer and a busy
peer look the same from the file, so this is a suspected stall, not
proof of one. On that wake, run one check; it handles the snapshot as
usual, so a `Ball:` or `Ask:` for you still gets its reply. A queued
wake can arrive late, so first apply any ending (a `closed — confirmed`
entry, the user's stop, or a passed `Window:`; **Ending** below), then
re-test the condition: if the snapshot's newest `Ball:` no longer names
the peer, or the live file's modification time is now within the limit
the wake line names (`(limit N minutes)`; the Codex launcher copies it
into the queued check), the wake is stale: write no `stall check`.
Otherwise append exactly one entry titled `stall check`, `Ball:` the
peer: in `Done:`, the peer's last entry and what you can observe of
its named job or artifacts; in `Ask:`, a request for its status. If
your previous entry is already a `stall check` with no peer entry since,
send `Ball: user` instead, with the open question and a default. The
append changes the file, so the alarm repeats only after another
silent period, and `Ball: user` ends it. Never take over the peer's
work on this wake.

The file's modification time is not proof of activity. A `touch`, an
editor save, or a copy resets it without progress, and a wrong clock
moves it. Change the live handoff only by appending. The alarm depends
on the other agent's watcher running and its host handling the wake.

The alarm detects the silence a stuck private wait causes; it cannot
interrupt or repair that wait, so the waiting agent prevents it. Wait
for a background job by its exact process or session identifier, or by
a completion file the job writes, never by a name or pattern search
that can match the waiting command itself. A tmux session name is
matched exactly and quoted, because zsh expands an unquoted `=name`:
`tmux has-session -t '=job-name'`. Give every wait a deadline,
and on the deadline report in the handoff instead of waiting again. A
long job's holder posts a short progress entry at least every 25
minutes.

The watcher is `scripts/clodball-watch` in this skill's directory (the
directory that holds this SKILL.md). Three arguments: the agent, the
handoff path, and the cursor, a nonnegative line number. Omit the
interval; the script defaults it to 30 seconds:

```sh
<skill dir>/scripts/clodball-watch <claude|cx> <absolute handoff path> <last-read-line>
```

A fourth argument, an explicit interval before the cursor, is still
accepted for a caller already passing one. Do not pass it from a new
launch: a session re-arms from the command it remembers, and a
remembered interval can revert after a context compaction. A session
still passing an interval adopts the three-argument form with
`/clodBall stop` then `/clodBall`; the restart reads from the saved
cursor (**The check**, step 1), so nothing is skipped.

It prints one line, `clodball: new entry for <agent> in <path>`, and
exits 0 when an unread peer field needs a check. On a suspected stall
it prints `clodball: stall suspected for <agent> in <path> (limit <N> minutes)`
and exits 0;
a new entry takes priority over a stall. It scans immediately,
so an entry appended between the snapshot and re-arming still wakes it.
Exit 2 means invalid arguments or an unreadable handoff file.

Capture the read boundary from the snapshot, never from the live file
at watcher startup:

```sh
snapshot=$(mktemp)
cp "$handoff" "$snapshot"
last_read_line=$(wc -l < "$snapshot" | tr -d '[:space:]')
# Read and handle this snapshot before launching the watcher.
"$skill_dir/scripts/clodball-watch" "$agent" "$handoff" "$last_read_line"
```

Retain the snapshot while handling it. Remove the owned scratch file
after the cursor is saved. If a read or check fails, keep the previous
cursor so the next check can retry the unread entries. Report the failure
and delay re-arming for one 30-second interval in the owned background
job. Do not immediately re-arm with the unchanged cursor: the first scan
would wake again on the same entry. Keep that delay cancellable by stop.

- Claude: `/clodBall` arms it as a Bash `run_in_background` call
  with `claude`, the handoff path, and the snapshot's cursor. The
  job's completion notification is the wake: run one check, then arm
  it again with the new cursor. The user never types the watcher
  command.
- Codex: run the packaged launcher in a session-owned tmux window:
  `scripts/clodball-codex <thread-uuid> <absolute-handoff-path> <saved-cursor> <absolute-state-dir>`.
  Resolve the script from this skill's directory. Keep `codex` on PATH
  and use a state directory owned by this session, with no overlapping
  launch. The launcher uses the watcher's default interval, validates
  its wake (a new entry or a suspected stall, named in the queued
  message), queues exactly one check, validates Codex's confirmation,
  then monitors for `started` for up to five minutes without a model call.
  A missing acknowledgement produces `alert.txt` and a terminal warning;
  it never resends. A busy thread can exceed this window without a stall.
  `current-run.txt` names the latest directory under `runs/`; each run
  preserves timestamped queue, start, and handled receipts and diagnostics.
  The root `phase.txt`, `wake.out`, `wake.err`, `queue.out`, and `queue.err`
  show the latest launch. Inspect old runs directly or pass their directories
  to `scripts/clodball-status`. `queue-outcome-uncertain` means inspect
  the receipt before retrying: the check may already be queued.
  The callback supplies `scripts/clodball-codex ack started|handled <run-dir>`
  commands. Use its exact run directory, even after a later launch.
  `CLODBALL_ACK_TIMEOUT` overrides the five-minute window in seconds.
  The queued check reads a new snapshot and re-arms with its cursor.
  Re-arm with `tmux respawn-window -k` targeting only the owned window;
  this replaces any monitor still sleeping after `started`. Never send
  a launch command as keystrokes to a pane that may still be running.
  Do not re-arm in an autonomous shell loop: delivery is not a completed
  read. On failure, preserve the cursor and report the failure. A Codex
  scheduling tool, if exposed, is an acceptable substitute at the
  3-minute fallback cadence: it is a model check, not a watcher.
- Keep one watcher or timer per session. Track its job or tmux window
  identifier and stop it when the session or collaboration ends. A
  restarted session checks the file before re-arming. Verify the saved
  snapshot and numeric cursor before launching the watcher.
- Known limit of the `codex queue` route: the queued check runs only
  when the Codex thread is idle. While Codex is in a long work turn its
  tick is delayed until the turn yields. A queue receipt proves acceptance,
  not that a check started or completed. A missing acknowledgement flags
  that observation gap; it does not establish why the check did not run.

## Ending: the goal decides, both agents confirm

1. An agent that judges the kickoff's `Done-when` met appends an entry
   titled `closed`, with the evidence of that check in `Done:` and
   `Ball:` the peer. When follow-up work remains, such as landing or a
   release, the entry names its owner and where its outcome will be
   recorded.
2. The peer's next tick re-runs the `Done-when` check itself. Met: it
   appends `closed — confirmed`, `Ball: none`, stops its timer, and the
   collaboration is over. Not met: it replies `revise` with what is
   missing, and the loop continues.
3. Every tick starts by looking for a `closed — confirmed` entry in the
   unread snapshot, using the same saved cursor as **The check**. Found:
   stop your timer without re-arming, append nothing, and tell the user
   in your session that the goal was met.

The loop also ends on the user saying stop, or on the kickoff's
`Window:` time passing, when it has one; then stop your timer and account for it: no unattended
waiters. A stop is never silent: the session that stops says so to the
user.

**A peer's `Ask:` never stops your timer.** Only a `closed — confirmed`
entry, the user's word, or the window does. If a peer asks you to stop
before the `closed` entry exists, nobody is left to confirm the close.
Answer such an Ask with `revise` pointing here, and keep ticking.

**A protocol test is not a collaboration.** An activation proof ends
with both timers stopped; project work needs its own kickoff entry and
its own timers afterwards. Say so in the `closed` entry, so the user
knows the loop has to be restarted for the real goal.

## Activation

Normal project activation is a complete kickoff entry and one reply
from the peer under `Re:` that names its timer. From then on the
routine is running; its stop is the goal-driven close above. A one-time
protocol test (one complete exchange, a quiet check that appended
nothing, and a stop that stopped both timers) is worth doing once per
machine, not per project.
