# Changelog - Second Brain Plugin

All notable changes to the second-brain plugin are documented in this file.
This covers plugin-level changes (hooks, tools, configuration, cross-cutting features).
For skill-specific changes, see the CHANGELOG.md in each skill's directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.16.1] - 2026-09-18

### Fixed
- **`ccfind` works on Linux and under Herdr; all three of its actions were broken there.** The tool assumed
  macOS inside tmux. On a Linux host launched from a Herdr keybinding, every mode failed and every action
  failed, in three independent ways.

  *The cache age read poisoned itself.* `cache_age` chained the two `stat` forms with `||`, BSD first. That
  relies on the wrong-platform binary failing silently, and GNU `stat` does the opposite: `-f` means
  `--file-system` there, so it prints a filesystem block on **stdout** and exits 1. The fallback then appended
  the real epoch to that block, and the arithmetic died on the word `File` under `set -u`. `cache_age` returns
  early when no cache file exists, so this only fired once a cache was present — every run but the first, and
  never on macOS, which is why a smoke test on a cold cache passed. Now branched on `$OSTYPE`, the way
  `kb-lint` already did it, so neither platform depends on how the other one fails.

  *`Ctrl-Y` had no clipboard.* `pbcopy` is macOS-only. `copy_to_clipboard` now tiers pbcopy → wl-copy → xclip
  → OSC 52 → tmux buffer. OSC 52 is what fires on a headless host: there is no local clipboard worth writing
  to, so the text goes to the terminal at the far end of the SSH session, and Herdr relays a pane's OSC 52
  write to its attached client. The call site reports failure instead of letting `set -e` kill the UI before
  the confirmation line prints.

  *`Enter` and `Ctrl-O` called tmux unconditionally.* Herdr is not tmux, sets no `$TMUX` and runs no tmux
  server, so both died with `failed to connect to server`. `open_alongside` now branches on the variable each
  multiplexer owns rather than on which binaries exist — a host can have tmux installed with no server
  running. Under Herdr it splits rightward and runs the command in the new pane.

  Three things about the Herdr path were wrong on paper and only showed up against the real binary, because
  every test ran from a shell while the tool is launched from a keybinding.

  *`--focus` is not the default.* `tmux new-window` switches to the new window; Herdr creates panes in the
  background, and omitting `--no-focus` is not the same as passing `--focus`. Without it the actions looked
  completely inert while working perfectly — `nvim` was running the whole time in a pane nobody could see,
  and the only visible evidence was a stray process.

  *A popup has no pane identity.* Herdr runs a keybinding's command directly rather than through a login
  shell. So `$PATH` is not the one the shell profile builds and `command -v herdr` finds nothing — the binary
  now resolves through `$HERDR_BIN_PATH`, which Herdr injects into every pane for this purpose. And a popup's
  `HERDR_PANE_ID` is deliberately removed, leaving no own pane to split; the target falls back to the focused
  pane from `herdr api snapshot`, which is the pane the popup is covering and what "beside this" means to
  someone looking at the screen.

  *The reply shapes differ.* `pane split` returns the new id under `.result.pane`, `tab create` under
  `.result.root_pane`. Ids are read from the reply, never predicted.

  Regression cases 39 and 40 cover all of it: a warm-cache run, clipboard tier selection, the tmux branch, the
  Herdr split, that the new pane is focused, a popup-shaped invocation with Herdr off `$PATH` and no pane id,
  an unusable binary, and no multiplexer at all.

## [2.16.0] - 2026-09-16

### Changed
- **A recap reuses the subject's pane when it is at a shell prompt, splits otherwise; manual launches run
  inline at a prompt.** One rule covers both ways in: run where the shell is free, otherwise beside it. A
  person leaves a pane sitting at its prompt after exiting a session, so that pane is the natural home for
  that session's recap, and a new pane for every recap was clutter. A `--manual` launch typed at a prompt now
  takes over that pane directly, with no Herdr call at all, and hands the prompt back when the recap ends; run
  from inside a Claude session's Bash tool it still splits, because that pane is busy.

  "Free" is Herdr's own definition of an available shell pane, read from `pane process-info` rather than
  guessed from a prompt pattern: `foreground_process_group_id` is the process group that owns the pane's
  terminal, `shell_pid` is its root shell, and `foreground_processes` lists what is in that group. `agent
  start` decides availability from the same fact but cannot be used here, having no way to carry the child
  wrapper's inline markers, so reuse is a `pane run` after the check.

  Freeness has two halves under `--auto`, and the second is not redundant. A shell hands each job its own
  process group, so a shell that owns the foreground normally owns it alone — an idle pane reports one
  process, `zsh`, while this pane with Claude in it reports a different group id and twenty-one. A second
  process inside the shell's own group is therefore something running without a group of its own, and the
  pane is busy however the ids compare. The count is read with `-le 1` rather than `-eq 1` so that a Herdr
  build which does not report the list at all answers zero and cannot quietly switch reuse off. It does not
  transfer to `--manual`, where the group is ours and holds us, so counting would only count ourselves.

  Two things about that check were wrong on paper and are worth recording, because both were measured rather
  than reasoned about and both would have shipped a feature that did nothing.

  *The comparison is not the same in both modes.* The rule was specified as `foreground_process_group_id`
  equals `shell_pid`. That is right for `--auto`, which is detached and outside the pane, and structurally
  wrong for `--manual`, which is running *inside* it: a script typed at a shell prompt becomes the pane's
  foreground process group itself, so the shell's own group is precisely what a free pane does not report.
  Measured — a script at a zsh prompt has pgid equal to the tty's foreground group, while the same script
  under a Claude session's Bash tool sits in its own group beneath `claude`, which holds the foreground.
  Comparing against `shell_pid` would have called every manual launch busy and left the inline path
  unreachable. So the question is the same in both modes, "is anything except us holding this pane", and only
  the vantage point differs: the shell under `--auto`, our own process group under `--manual`.

  *The launcher has to wait, and it was not waiting.* The design assumed this process already waits for the
  ending session to exit before it decides. It does not; `recap_child.sh` does, and that runs after the pane
  decision. Since the launcher is spawned by the ending session's own SessionEnd hook it is a descendant of
  that session's `claude`, so `claude` is necessarily still alive and still owns the pane's terminal at that
  instant. Measured directly: `CLAUDE_PID` in the hook environment is the very number `pane process-info`
  returns as `foreground_process_group_id`, with `shell_pid` its parent. A single check would therefore have
  read `busy` every single time and reuse would never once have engaged. The launcher now waits for the pane
  itself to come free, which is the condition the decision actually needs, bounded at ten seconds so that a
  pane claimed for something else cannot hold a recap up — when the window closes on a busy pane the split
  runs, exactly as before. The wait costs nothing anyone is waiting on: this process is detached and off the
  hook's clock. A pane that has been closed answers nothing and is not waited on at all, since it will not
  come free and the split will fail against it too, which is what leaves the subject `requested` for the
  notice.

  This is the sort of defect a test can hide rather than catch. The first version of the new cases used a
  stub that answered "free" on its first read, so they passed whether or not the launcher waited — validating
  the code against the design's assumption instead of against the machine. The stub now reports busy twice
  and then free, the real sequence, and a differential run with the wait disabled turns six assertions red.

  Reuse adds one risk a fresh pane did not carry, and it is left standing on purpose. `pane run` submits text
  to a shell, and several situations a person would call busy read as free here, because `process-info` reads
  processes rather than the line editor or the job table: a prompt with something typed at it but not yet
  entered, a job suspended with Ctrl-Z (which hands the terminal back, so the foreground group is the shell
  again and holds only the shell), and anything the shell runs inside its own group instead of a job of its
  own — a shell function, a compound command, a `read` prompt. In each case the recap command lands somewhere
  it does nothing. The shell then reports a command it cannot find,
  the subject stays `requested`, and the next notice offers it — visible, and costing a recap rather than any
  data. Clearing the line first would buy the recap by discarding what someone was in the middle of typing,
  which is the worse trade.

- **`recap_child.sh` changes into the vault before starting `claude`.** Reuse brings no `--cwd`, and the
  split passed the vault for a reason: it keeps the work repo's own project settings and instructions out of
  the recap's context. Doing it in the child instead makes it hold however the recap was started — reused
  pane, fresh split, or a command pasted into some other terminal. `get_kb_path` was already in scope through
  `obsidian_helpers` and `resolve_project`, so this needed no new dependency.

  Nothing renames the reused pane. It still carries the subject's name, and the recap session's own
  SessionStart renames pane and agent to the recap name just as it does for a split; claiming the label
  before anything had run would tell a watcher the wrong thing if the hand-off failed. After the recap the
  pane returns to a prompt carrying the recap's label, and the next session started there renames it.

### Added
- Case 38 of the regression suite: twenty-five assertions over the documented reuse scenarios — an idle
  pane hosting the recap with no new pane and no rename of ours, a busy pane getting a split beside it, a
  manual launch at a prompt running inline with the vault as its working directory and Herdr only read and
  never told, a manual launch from inside a Claude session splitting, and a closed pane leaving the subject
  `requested` for the notice, plus a pane whose ids agree but whose foreground group holds a second process.
  Three of them exist only to pin down the wait: that `--auto` polls a busy pane, that it gives up rather
  than queue, and that `--manual` asks once, since a person standing at that prompt is not going to change
  their mind by being polled.
- `SECOND_BRAIN_PANE_WAIT_ATTEMPTS` overrides the pane wait's twenty half-second attempts, following
  `SECOND_BRAIN_LOCK_ATTEMPTS`. It exists so the suite can assert the give-up path without spending ten
  seconds on it.

### Fixed
- **The subject folder is made absolute before anything is built from it.** The string outlives the directory
  it was typed in, and the child now changes into the vault before using it, so a relative path handed to
  `--manual` would afterwards resolve `recap.log`, the note the exit check reads, and the folder given to the
  status writer against the vault instead. The silent case is the one that matters: a relative path that also
  exists under the vault writes to a different session's note with no error. The split and paste paths already
  had this exposure through their own `cd`; one line at the top covers all three.
- **Case 34's stub was answering as a pane that no longer exists.** It reported `shell_pid` with no
  `foreground_process_group_id`, which `pane_state` reads as `gone`. Its "it splits the ending session's pane"
  assertions kept passing, but through the closed-pane branch rather than the busy one they were written for —
  the split looks identical from the outside, which is exactly what hid it. The stub now reports the ending
  session's claude holding the pane, and a new assertion pins the read count at two so the case cannot drift
  back to the wrong branch unnoticed.
- **The no-poll assertion was in the one case that could not fail it.** It sat under a free pane, where the
  wait loop is skipped whether or not it is scoped to `--auto`; deleting the mode guard left the count at one
  and the assertion still passed. Moved to the busy `--manual` case, where removing the guard now turns it
  red at three reads.
- **The pane wait's attempt count is validated rather than trusted.** An unusable value made `-lt` fail with
  "integer expression expected", so the loop body never ran and the wait collapsed to exactly the single
  check it exists to avoid — with the complaint going to the `/dev/null` this process is detached onto, so
  nothing recorded it. The machine-supplied process count was already guarded this way; the one a person can
  set was not.
- **Nothing pinned the rule that the launcher never writes the subject's status.** Found by mutation: a status
  write inserted into the reuse branch left all twenty-five reuse assertions green. Only the end hook, before
  the launch, and the child, after it, may move a subject; the launcher hands over and records to `recap.log`.
  Both reuse and split now assert the subject is still `requested` when the launcher is done.
- **The reuse failure branch was unreachable in the suite.** The stub had no `pane run` case, so every reuse
  succeeded and the two `--auto` contracts — never print, never exit non-zero — were pinned on the happy path
  alone. A new state makes a free pane refuse the hand-off, and asserts all four contracts on it: exit 0,
  silence, the reason in `recap.log`, and the subject left `requested` for the notice.

## [2.15.1] - 2026-09-16

### Fixed
- **A signal trap released the recap lock and then carried on holding nothing.** The end hook installed one
  bare handler on `EXIT HUP INT TERM`. Bash runs a signal handler and then *resumes* the script, so on TERM
  the hook released the lock and continued straight through the read-rebuild-write with nothing held. That is
  precisely the lost-update window the lock exists to close: a `done` written by a recap in that gap would be
  read, discarded and overwritten by the rewrite. It also made the hook ignore TERM outright, which is
  surprising for anything a harness may signal before escalating.

  Only `EXIT` wants a handler that returns. The three signals now exit, with the conventional 128 plus
  signal number, so a TERM leaves exit 143, no lock, an intact note, and no unlocked rewrite. Verified in
  isolation first, because the semantics are the whole bug: with a bare handler the line after the work
  still runs, and with an exiting handler it does not.

  `recap_status.sh` is deliberately left alone. `EXIT` alone is correct there, and although an untrapped
  signal would leak its lock, that process is short-lived and the sixty-second staleness breaker covers it.

  Worth being exact about what this covers, because it is narrower than it sounds. The traps are installed
  after the recap stamp has already landed, so they govern the locked rewrite and nothing else. Everything
  before that line runs with no trap at all, so a signal there takes the default action and terminates with
  nothing stamped — which was equally true before this change, since the previous version cleared its traps
  before the predicate ran. This commit neither opened that window nor closed it; what made it small was
  moving the stamp to the top in 2.15.0, so it is now one batched property read and one bounded grep wide.
  There is therefore no trade here: during the rewrite the new behaviour dominates the old one on every axis.

  One question is left open next to the traps rather than guessed at: which signal Claude Code uses to cancel
  a hook. If it is SIGKILL then no trap takes part in a cancellation at all, the lock is leaked and broken
  later by the staleness rule, and the TERM path matters only for a closing terminal, a manual kill or a
  supervisor. The double-fork result points that way, since a tree-walking kill is what defeated a bare
  `setsid`.

  This defect and a wrong conclusion I drew were the same thing. The SIGTERM differential I ran to justify
  the previous commit's reordering showed no difference between the two orders, and I read that as "the
  ordering does not matter" when the truth was "my instrument is broken": the trap swallowed the signal, so
  the hook completed either way. SIGKILL was the only instrument that could see it. The rule worth keeping
  is that a hook under test must be killed with a signal it cannot trap, or the test measures the trap.

- Three assertions guard the shape: no bare handler on a signal, every signal trap exits, and `EXIT` keeps
  the one that returns. 228 pass.

## [2.15.0] - 2026-09-16

Two rulings from the planning session, and a correctness fix its ordering argument uncovered.

### Fixed
- **A cancelled SessionEnd hook dropped the session out of the recap pipeline, silently.** The stamp was the
  last thing the hook did, after the memory copy and the note rewrite. Measured under `SIGKILL` at every
  point from 0.3 s to 1.1 s, the old order left `recap_status` empty every time: the note looked complete,
  and the start-of-session notice skips an empty status, so the session was never recapped and never
  described, with nothing visible to say so. The predicate and the stamp now run **first**, before the lock
  and before the rewrite. Same kills, same transcript: `requested` every time. This matters because the hook
  costs about 1.6 s against a default budget of 1.5 s, so cancellation is the normal case, not the edge.

  The failure inverts to the better one. A hook cancelled after the stamp leaves a note missing `ended_at`
  and `duration_seconds`, which is visible and which the recap can work around, for a session that will
  still be recapped. Both reads the predicate needs are safe outside the lock: `recap_of` is written once at
  registration and never changes, and a stale `recap_status` only makes the compare-and-set writer refuse a
  transition, which is the safe direction.
- **The note rewrite could be observed truncated.** `write_session_md` used a plain redirect, which empties
  the target before filling it, and the hook reaches that line at about 1.4 s against a 1.5-second budget,
  so a cancellation can land inside the write. What a half-written note loses is the `## Transcript` pointer,
  which under the reference-only architecture is the only record of where the conversation lives. It now
  writes through a temp file and renames, like every other writer here, and returns non-zero rather than
  leaving a partial note if the write itself fails. Verified with seven kills straddling the rewrite: no
  truncated note, no leftover temp file.

### Added
- **`recap_status.sh <folder> clear --force`**, the documented way to recap a session again. The status only
  moves forwards, so `requested`, `done` and `failed` are all dead ends to the end hook, which acts only on
  a status that is empty or `exempt`. Nothing automatic may un-request a subject, which is why this is a
  removal rather than a transition, why it needs `--force`, and why it is logged as `reset <from>->empty`
  beside the writer's own lines. `--force requested` is unchanged and still re-stamps a subject that is
  done or stuck. This closes a gap that had forced a hand edit of a real note.

### Changed
- **The recap skill verifies its claim instead of re-taking it.** In every sanctioned path the wrapper has
  already moved the subject from `requested` to `running` before `claude` starts, so Phase 1.0's old
  instruction to claim it produced a guaranteed refusal and told the skill to stop every single time. It was
  visible in a real run as `refused running->running` in the log, 43 seconds after the child's own claim.
  The skill now reads the status and decides: `running` with its own `recap_of` naming that subject means the
  claim is already its own, so it proceeds and makes no writer call; `requested` or `failed` means the
  wrapper never claimed and it claims now; `done`, an empty status, or `running` under a different subject
  mean stop. A refusal is fatal only when this session is not the registered recap session for the subject.
- Batch triage says the same thing from the other side: a batch claims each subject itself, because no
  wrapper ran for the ones it picks up.
- The regression suite clears six Herdr variables rather than four. `HERDR_SOCKET_PATH` is the channel to
  the running daemon, so the real binary reaches the live workspace through it whatever pane id it is handed,
  and `HERDR_BIN_PATH` is an absolute path that would bypass `PATH` order and the tripwire with it. Nothing
  in the plugin reads the second one today, which makes it latent rather than live.
- Seventeen new assertions: `clear` from every state with the rest of the note intact, that it refuses
  without `--force` and takes no description, that `--force` still serves only `requested` and `clear`, that
  every reset is logged, that the stamp precedes both the lock and the rewrite, and that the two extra Herdr
  variables are cleared. 225 pass.

## [2.14.1] - 2026-09-16

### Fixed
- **The regression suite could open real Herdr panes.** It split the pane of the session running the tests,
  twice, and pointed each new pane at the scratch vault the suite then deleted, so both arrived dead. Only
  a test fault, never reachable in normal use, but it left debris in a real workspace.

  Clearing `HERDR_PANE_ID` per invocation was not enough: the launcher resolves the binary itself with
  `command -v herdr`, falling back to `$HOME/.local/bin/herdr`, so any call site that forgot to clear the
  detection variables, or that reached the launcher through an `eval` of a printed command, picked up the
  real binary and a real pane id from the ambient environment. The suite now makes the environment hostile
  once at the top instead of per call site: a tripwire `herdr` first on `PATH` that records the attempt and
  exits non-zero, so `command -v` can never resolve the real binary and the fallback is unreachable, and the
  detection variables cleared for every child so the launcher's gate is shut unless a case opens it with a
  stub of its own. Case 36 asserts the tripwire log is empty, so reaching the real Herdr is a test failure
  rather than a surprise in someone's terminal.

  The specific call site that leaked is not identified. With the guard in place nothing reaches Herdr, and a
  diagnostic run with the gate forced open produced no tripwire entry either, so the reproduction is gone
  along with the hole. What is known: the path in both panes was the suite's scratch vault, and the command
  carried a real `SECOND_BRAIN_PARENT_PID`, which only `--auto` sets. The likely candidate is the one
  `--auto` case that inherits the ambient `CLAUDE_PID`.

## [2.14.0] - 2026-09-16

Stage 2 of the recap work: `auto_recap: on` starts the recap itself, in a session of its own, inside
Herdr. Everything else about a recap is unchanged, because Stage 1 already shipped the launcher, the
child, the status protocol and the notice; this adds one call site and the `--auto` behaviour behind it.

### Added
- **`recap_launcher.sh --auto`**, called by `session_end.sh` when `auto_recap` is `on` and the size test
  passed. It splits the ending session's Herdr pane, waits for the new pane's shell, labels it, and runs
  the recap child there with the subject, the name and the ending session's pid as inline assignments on
  the command. Never `--env`: Herdr documents that as pane-lifetime, so every later session in that pane
  would inherit the marker, register as a recap and be stamped `exempt` at its own exit.
- **It has no terminal, so it writes to the subject's `recap.log`** rather than stdout, the same file the
  child and the status writer append to, so one file tells the whole story of a recap. Outside Herdr it
  does nothing and says so there: `on` degrades to `notify`, the subject stays `requested`, and the
  start-of-session notice covers it. A failed split or hand-off is logged and exits 0, never non-zero into
  a hook that has already gone.
- **`spawn_detached`**, which is how the launch survives. Measured against a project-level SessionEnd hook
  that overran its timeout: when Claude Code cancels a hook it kills the hook's whole process tree. A child
  backgrounded with a plain `&` died, and so did one that called `setsid` and exec'd, because that leaves
  it a direct child and a tree walk still finds it. Only a double fork survived, the intermediate exiting
  at once so the worker is reparented away from the tree being walked. With the same hook exiting normally
  all three survived, so this matters exactly when a SessionEnd hook is under time pressure, which is
  always.
- **The pane readiness wait.** `pane split` returns as soon as the pane exists, which is before its shell
  can accept text, and `pane run` submits text plus Enter to that shell, so text sent too early is simply
  lost and leaves a correctly labelled pane at an empty prompt. The launcher polls `pane process-info`
  until it reports a `shell_pid`, which is a fact about the pane rather than a guess at what a prompt looks
  like, so it holds whatever shell and theme are in use. It costs nothing anyone waits on, since the
  launcher is detached by then.
- **Regression cases 34 and 35**, seventeen assertions against a stub Herdr that records every call: the
  split targets the ending session's pane, no `--env` is ever used, the shell is waited for, the pane is
  labelled before anything runs in it, the markers and the parent pid travel inline, a failed split is
  logged and exits 0, `notify` and `off` launch nothing while `on` launches exactly once, and a detached
  child outlives a `SIGKILL`ed parent.

### Changed
- The launch goes **after** the `requested` stamp, never before. A recap claims its subject by moving
  `requested` to `running`, so a child that won that race would find an empty status, be refused by the
  transition table, and exit having done nothing.
- `SECOND_BRAIN_PARENT_PID` now carries the ending session's `CLAUDE_PID`, verified present in the hook
  environment. Until this stage the child's wait-for-parent loop had nothing to wait on and was dead code;
  it is what stops the recap reading a transcript the ending session is still flushing.

### Known limits
- **`on` needs the SessionEnd budget raised.** The launch is the last thing the hook does, so if the hook
  is cancelled at its budget first, nothing is launched and the session stays `requested` for the notice.
  That is a safe degradation rather than a fault, but it means `on` is only reliable with
  `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` set, for the reasons in the 2.13.0 Performance section.
- **Herdr only.** Anywhere else `on` behaves as `notify`. Stage 3 in the plan covers the headless and
  scheduled alternatives, and is deliberately not built.

## [2.13.0] - 2026-09-15

Sessions now keep track of whether their knowledge has been distilled. When a session ends the hook records
whether it needs a recap; a recap runs in a session of its own and writes the subject's description as well
as its outcome. Nothing is deleted and nothing runs unless you switch it on. See
`docs/adr/0002-recap-status-lives-on-the-session-note.md`,
`docs/adr/0003-recap-sessions-are-registered-guarded-by-env.md` and
`docs/adr/0006-the-description-is-written-after-the-session-ends.md`.
### Performance

The SessionEnd hook does not fit its budget on a large session, and did not before this release either.
Claude Code gives all SessionEnd hooks **1.5 seconds together**, and on a session with a 4 MB transcript
and an 80-file memory directory this hook measured **1.5 to 1.6 s at 2.12.0** — already at the limit — and
**1.9 to 2.0 s** once this release's recap work was added. Past the budget the hook is cancelled, which
reads as `SessionEnd hook ... failed: Hook cancelled` on exit even though the note has already been
written and stamped, because the cancellation lands after the work.

Three cuts bring it back to **1.7 s**, roughly where 2.12.0 was:

- **`read_frontmatter_props`**, a batch reader: one pass for all fifteen scalars the hook needs instead of
  one `sed | grep | sed` pipeline each. Forty-five processes become one, worth about 0.30 s. It returns one
  line per property in the order asked, and applies the same quoted-versus-plain unescaping branch as the
  single reader, which the suite checks value for value.
- **One `jq` pass for the payload**, as `session_start.sh` already did, rather than three.
- **The predicate reads `recap_status` and `recap_of` from that batch** rather than reopening the note.

What this does not do is make the hook fit reliably. The remaining 1.7 s is a long tail of per-line process
spawns across a 280-line script, with no single dominant cost, and the corpus holds transcripts ten times
larger than the one measured. A plugin cannot raise the budget: timeouts on plugin-provided hooks are
documented not to. Raising it is the user's to do, either with `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` in
milliseconds or a per-hook `timeout` in a settings file, and `auto_recap: off` does **not** avoid the
problem, since the hook was already at the limit without it.


### Added
- **`auto_recap`**, off by default, with three values. `notify` stamps `recap_status` on a session's note as
  it ends and shows the pending ones the next time you start a session. `on` also launches the recap, and
  needs Herdr in this version. `off` writes nothing and shows nothing. A config that cannot be read reads as
  `off`, so a broken config disables the feature rather than enabling it.
- **`skills/common/recap_status.sh`**, the only writer of `recap_*` and, after a session ends, of its
  description. It is compare-and-set rather than a setter: each transition has one legitimate writer, and
  anything outside the table changes nothing, exits 3 and is logged to the session folder's `recap.log`.
  Twenty concurrent claims on one subject yield exactly one winner, which is what stops a hand-run retry and
  a launched recap from both producing a daily log for the same session.
- **A per-folder lock**, `mkdir`-based because macOS has no `flock`, shared with `session_end.sh` through
  `recap_lock_acquire`/`recap_lock_release`. The end hook holds it across its whole read-rebuild-write, so a
  `done` written by a recap while that rewrite is in flight can no longer be read, discarded and overwritten.
  It releases before stamping, since the stamp takes the same lock and nesting would deadlock the hook
  against itself; each half is atomic and the transition table refuses whatever slipped into the gap.
- **The SessionEnd predicate.** On a true ending it stamps `requested`, or `exempt` for a session too small
  to carry knowledge, and it touches nothing that is already `requested`, `running`, `done` or `failed`. A
  `/clear` or a resume stamps nothing, because neither ends the work. `exempt` is re-evaluated on every
  later exit, so a session resumed after a small start becomes `requested` once it has done real work.
- **The start-of-session notice**, in `systemMessage` so it reaches you rather than Claude's context: a
  retry command Claude can see and you cannot is useless, and a recap instruction in Claude's context invites
  it to run a multi-minute recap in the middle of your work. It lists failed recaps first, then pending ones,
  newest first, at most five over fourteen days, and never lists a recap that is done, a session that is
  exempt or was never requested, or a recap session. One `awk` pass over the window, matching a status with
  or without quotes because Obsidian strips quotes when a person saves a note. The whole notice costs
  0.09 s on a vault of 525 notes across 158 date directories.
- **`hooks/scripts/recap_launcher.sh --manual`** and **`hooks/scripts/recap_child.sh`**. The launcher opens a
  Herdr pane, or prints the command to paste when there is no Herdr, and passes the subject marker and the
  name **inline on the launched command** — never through the pane's environment, where every later session
  in that pane would inherit it, register as a recap and be stamped exempt at its own exit. The child claims
  the subject, runs the recap in the foreground so you can watch it, and marks `failed` on the way out if the
  recap never reached `done`, so a closed pane surfaces in the notice instead of looking like work in flight.
- **A recap session is registered as one.** With the marker set on a genuine startup, its note records
  `recap_of`, takes its subject's domain rather than the vault's own directory, and carries the single tag
  `session-recap`. Its own exit stamps it `exempt`, decided by the note and never by the marker: honouring an
  inherited variable there would let any process that picked one up write off a working session's knowledge.
- **`set_frontmatter_list`**, the list counterpart of the scalar setter, needed because the recap writes the
  subject's tags under the status lock. Empty input writes nothing, since matching no canonical tag is not a
  decision to erase the tags a session inherited; a non-slug item is refused and logged rather than quoted
  around; and a bare `tags:` with no items, the shape of every fresh note, is a replace rather than an insert.
- **`tools/ccfind/`**: `recap_status` as a seventh field, and `--not-recapped` for the full backlog the
  notice deliberately does not show.
- **Regression cases 24 to 29**, 69 new assertions: the list setter's three rules, every legal and illegal
  status transition, twenty-way concurrency, stale-lock recovery, the predicate across nine transcript and
  reason shapes, the notice's contents and its placement, the launcher's inline markers, and recap-session
  registration. 167 assertions pass.
### Removed
- **The start-time derivation request and its stamp.** 2.12.0 had `session_start.sh` inject an
  instruction asking the model to run the session-manager skill in automatic mode, and stamp
  `metadata_requested_at` so it asked only once. Measured on the first real session to carry it, the
  instruction was ignored: five user prompts and thirty-nine assistant turns produced no tags, no
  property write and no skill invocation, while the stamp recorded a request that was never carried out.
  A hook's `additionalContext` places text in the model's context and compels nothing, so a request made
  that way cannot be relied on. The recap, which runs after a session ends and reads the whole
  conversation, writes the description instead (ADR-0006).
- `metadata_requested_at` is no longer written by anything. It stays on the notes that already carry it,
  travelling through the end hook's unknown-property preserve loop as before: it is inert, it records
  that a request was made on a day when one was, and removing it would be a delete for tidiness
  (ADR-0001). It is deliberately still absent from `KNOWN_PROPS`.

### Changed
- `skills/session-manager/SKILL.md` states ownership by stage rather than by writer: the hooks seed at
  registration and never overwrite, the skill is the only writer while a session runs, and the recap
  writes the description once the session has ended. The automatic-mode paragraph, which existed only to
  respond to the removed instruction, is gone.
- `skills/session-manager/tag-canonicalization.md` gives each mode exactly one writer. Its step 4 opened
  with the Obsidian CLI `property:set` command before the modes split, so a recap following it literally
  would have written tags through the vault, outside the lock the status writer holds, and either
  duplicated or contradicted the write inside it. The CLI command now belongs to interactive mode;
  automatic mode produces the canonical list and hands it to `recap_status.sh --tags`, writing nothing
  itself. Automatic mode is triggered by a recap describing an ended session, and may coin a tag the
  vault has never seen only on repeated evidence in the conversation, recording it as a proposal
  otherwise.
- Registration keeps every mechanical seed it had: the domain from the directory map, fork and delegate
  lineage and inheritance, the naming of an unnamed delegate, and the Herdr pane and agent rename.
- **The knowledge bank's schema documents the session note.** `_meta/schema.md` gains a Session Note
  Properties section: every property, who writes it, and the full `recap_status` transition table. The
  generator was updated so a new vault gets it; the live vault was hand-edited to match, because
  `generate_schema.sh` does not produce that file's study, source-type and stub sections and running it
  against a real vault would erase them. A generator that overwrites hand-written content is a delete in
  disguise (ADR-0001).
- **The recap decides a session's domain**, from the note, then the directory map, then the conversation,
  and it never prompts. See the session-recap changelog for the phase-by-phase detail.
- `skills/session-recap/SKILL.md` documents the launcher as the way in, since a slash command typed into an
  ordinary session now stops at the Phase 1.0 gate by design.

### Fixed
- **A session's prompts were counted with its tool results.** Both carry `"type":"user"`, so the recap's
  statistics read 1080 where the session had 42 prompts. `count_user_messages` counts prompt-shaped records
  and is reported as "User prompts (approx.)", with the raw number kept beside it under its own name. It is
  deliberately not what the predicate uses: measured across the vault, a five-prompt rule would have
  exempted a third of real sessions, several above a thousand lines, because sessions here are long
  autonomous runs on a handful of prompts. The predicate counts assistant records instead, which separate
  trivial from real with an empty band between four and ten, and it reads the head of the file rather than
  all of it.
- **The recap's project fallback could invent a domain.** `parse_transcript.sh project` called a detector
  that matched the working directory against project directory names and printed `unknown` when nothing
  matched, which is exactly the invented domain ADR-0004 exists to keep visibly missing. That script is
  removed and the command now reports the directory and the domain it maps to, as information rather than a
  decision.
- `tests/hook-regression-suite.sh` asserts the absence: case 11 now checks that a named startup is asked
  for nothing, which fails if an injection is ever re-added, and case 15 plants
  `metadata_requested_at` by hand so the unknown-property survival assertion still guards the preserve
  loop that `recap_status` depends on. Nine assertions that tested the removed mechanism are gone, 98

### Fixed after review

A code review of the above found fifteen defects, each reproduced before being fixed. Suite grows to 176
assertions. The ones worth knowing about:

- **A killed SessionEnd hook leaked the lock and blocked every recap of that session.** It acquired the
  lock 177 lines before releasing it and installed no trap, so a hook killed inside that window — by its
  own budget, a slow `git` call, a large memory directory to copy — left `.recap.lock` behind and every
  later writer was refused until the lock aged past a minute. Verified by killing the hook mid-run at
  seven points: all seven leaked before, none after.
- **The lock could consume the whole hook budget.** The acquire spun for the helper's default while the
  hook has about 1.5 s in total, and it paid that wait twice, once for its own rewrite and once for the
  stamp. A contended lock therefore risked the hook being killed *before writing the note at all*, losing
  `ended_at`, the duration, the transcript pointer and the rebuilt body: strictly worse than the lost
  update the lock exists to prevent. The hook now asks for a short wait and the stamp for a shorter one,
  and the acquire itself was restructured to check staleness once instead of once per iteration, since a
  `sleep` fork measures nearer 70 ms than the 50 ms requested. A contended end-to-end exit went from
  1.80 s to 1.16 s, and the uncontended one from 1.02 s to 0.86 s.
- **The staleness check could never fire outside macOS.** It read `stat -f %m`, which on GNU reports the
  filesystem rather than the mtime, so every lock read as age zero, no leaked lock was ever broken, and
  one leak would have disabled recaps for that session permanently. The same bug made every age in the
  notice zero, so no staleness threshold could fire. Both now try BSD then GNU, the idiom already used in
  `ccfind.sh` and the kb-lint scripts three files away.
- **The notice could tell you to recap the session you were sitting in.** A `/clear` fires the start hook
  with the same session id, so a session already stamped `requested` was offered as a candidate to itself.
  Following that advice reads a transcript still being written and marks the session `done`, after which
  its real exit sees a settled status and the real recap never happens. It now skips its own folder.
- **A recap stuck in `running` was a dead end.** There is deliberately no `running` to `running`
  transition, so the launcher command the notice printed was refused as "another recap holds the claim" —
  true of a process that no longer existed. The notice now prints the reopen instead, and lists a stale
  `running` in `notify` as well as `on`, which matters because `notify` is the only mode this version
  ships and a manual launch can die without its wrapper running.
- **The child reported every failure as "another recap holds the claim".** A lock timeout, a missing note
  and a plugin root that no longer exists all produced that message, and the last of those is realistic
  because the plugin cache holds several version directories. It also cleared its failure trap on them, so
  the subject sat `requested` with nothing recording why. Only a refused transition says that now; the
  plugin root is checked before anything is sourced.
- **`ccfind --not-recapped` reported an empty backlog after the upgrade.** The cache carries no version and
  is served stale-while-revalidate, so the new seventh field was missing from a cache an older version
  wrote and the filter matched nothing, reading as "everything has been recapped". A field-count mismatch
  now forces a synchronous refresh.
- **The launcher called a failed hand-off a success.** `pane run`'s exit status was discarded, so a failure
  left an empty pane open, the subject at `requested`, and the user told a recap had started. It also
  merged herdr's stderr into the buffer it parsed as JSON, where one warning line would have sent a
  successful split down the error path and orphaned the pane it had just made.
- **The notice printed commands that broke on a vault path containing a space**, and the launcher never
  passed `SECOND_BRAIN_PARENT_PID`, leaving the child's wait for the ending session dead — harmless for a
  manual launch, but that wait is the whole point of the Stage 2 path the launcher was written for.
- **The suite's twenty-way race ran with an empty HOME.** It passed `$4` to `sh -c`, which receives the
  word after the script as `$0`, so the scratch HOME never arrived. Harmless only because nothing in that
  path reads HOME today; the moment one did, twenty parallel writers would have reached the real config.
- Stale text the removals left behind: the recap skill's inventory grep passed four search roots and
  reported every hit twice, `resolve_project.sh` still described tag hints as feeding a derivation request
  that no longer exists, the recap README listed `metadata_requested_at` as a written property, and
  ADR-0002 still said the hook requests a recap only when the status is empty. `session-manager` also
  gained the changelog entry the repo's own policy requires for a skill whose behaviour changed.
  remain, and the suite ends the release at 167.

## [2.12.0] - 2026-09-15

Session metadata is now seeded when a session starts instead of waiting to be asked for. See
`docs/adr/0004-project-names-a-knowledge-bank-domain.md` and
`docs/adr/0005-delegation-is-declared-not-detected.md`.

### Added
- **`project` is a knowledge-bank domain**, resolved by a new shared `skills/common/resolve_project.sh` from a `project_domains` map in the plugin config. A map key matches a directory it equals or contains, and a key ending in `*` matches any path beginning with the stem, so one entry covers a family of sibling packages. The longest match wins. Anything unmapped resolves to empty, and so does any stored value outside the domain set, which is what lets older notes keep their directory basenames without a reader ever mistaking one for a domain. `list_project_domains` is the single source of truth every consumer validates against.
- **The name is taken from the hook's stdin.** `session_start.sh` now reads the `session_title` and `source` input fields, so `session_name` is written at registration instead of being recovered later from a transcript that is documented to lag.
- **Lineage properties `forked_from_name`, `delegated_by` and `delegated_by_name`**, and a `## Lineage` body section that both the start and the end hook regenerate from those properties. The section links the counterpart's full `_sessions/<date>/<id>/session` path with its name as the alias, because every note is called `session.md` and a bare link would be ambiguous across the whole vault.
- **Delegation is recorded when it is declared.** A launcher sets `SECOND_BRAIN_DELEGATED_BY` and `SECOND_BRAIN_DELEGATED_BY_NAME` inline on the launched command and the delegate's own hook records them. Honoured only when `source` is `startup`, so a variable that leaked into a shell cannot make every later session in it look delegated.
- **`skills/common/launch_delegate.sh`**, one thin helper that starts a delegated session with the marker set, names it `<role>-<launcher>` so the distinguishing part survives the 32-character agent-name limit, and opens a Herdr pane or prints the command when there is none.
- **Forks and delegates inherit** their source's domain and tags at registration. An untagged source leaves them untagged rather than falling through to the model, whose request would otherwise land in the middle of a fork's conversation or on top of a delegate's first instruction.
- **The hook asks for what it cannot derive.** A named session with no stamp gets an instruction to run the `session-manager` skill in automatic mode, carrying the resolved domain and the mapped directory's tag hints. Gated on a genuine startup with no declared launcher, no parent and a known name, and stamped with `metadata_requested_at` at the moment the request is made, so a session whose model never ran the skill is asked once rather than on every later start.
- **The terminal is named at startup.** The name is on stdin from the first event, so a freshly launched session no longer sits in an unlabelled pane until its first resume.
- **`--set` and `--set-domain`** in `setup_kb_path.sh`, both read-modify-write, and `get_plugin_config_value` in `get_kb_path.sh`, which falls back on every failure so a broken config disables a feature rather than enabling it. A domain that does not exist in the bank is refused rather than stored.
- **`set_frontmatter_prop`, `yaml_escape`, `session_folder_relpath` and `session_lineage_body`** in `skills/common/obsidian_helpers.sh`.
- **Regression cases 9 to 15** in `tests/hook-regression-suite.sh`, 49 new assertions: the resolver's boundary, wildcard, longest-prefix and out-of-set rules, config preservation, the full injection gate, a stray marker on a resume, fork and delegate inheritance including the untagged case, the quoted-marker false positive, and lineage backfill at exit.

### Fixed
- **A conversation that merely quoted another session's registration line was read as its fork.** `transcript_forked_from` matched the marker text anywhere in the first 200 lines. It now also requires the record to be an `attachment`, which is the only shape a replayed marker has; verified against four fork transcripts in the corpus. A session that reads a hook script or another transcript early, which a recap session does, was the case at risk.
- **Notes rebuilt mid-session no longer invent a project.** `rebuild_session_md` computed its own `basename "$cwd"`, so a note recovered at resume, pre-compact or exit kept getting a directory name after the change. It calls the shared resolver, and writes the lineage properties, so a rebuilt note matches a freshly registered one.
- **`--configure` no longer discards the rest of the config.** It rewrote `config.json` wholesale from a heredoc, which would have wiped the domain map and any other key on every reconfigure.
- **The start hook's output is built with `jq`** instead of a heredoc. Two of the strings it carries are chosen by a person, and a single quote in a session name produced invalid JSON that silenced the hook for every consumer of it.

### Changed
- `session_end.sh` backfills `forked_from_name` alongside `forked_from`, never tags: inheritance belongs at registration, where a fork had not yet done work of its own to describe. It also manages the three new lineage properties, while `metadata_requested_at` flows through the unknown-property preserve loop untouched.
- `skills/session-manager/SKILL.md`: the ownership rule now reads as hooks seed at registration and the skill is the only mid-session writer; `project` is described as a domain from a closed set; the report gains a lineage line.
- `skills/session-manager/tag-canonicalization.md` step 4 splits into interactive and automatic modes. Automatic writes tags that already have a canonical form without asking, reports any it could not match, and never prompts, so a derivation never interrupts the user's first request.

### Removed
- `skills/common/detect_project.sh`. Its `basename "$cwd"` was the single reason a session note ever recorded `data`, `src` or a bare home-directory name as a project.

### Fixed after review

A code review of the above found fifteen defects, each reproduced before being fixed. The ones worth
knowing about:

- **A quote in a session name could leave a whole note unparseable.** `read_frontmatter_prop` stripped the surrounding quotes but not the escaping inside them, so a value read off a note and written back was escaped twice. Seeding `session_name` from the launch name made this reachable on a session's first exit rather than never. There is now a `yaml_unescape` inverse and reading applies it, so a value round-trips unchanged however many times it passes through.
- **Unescaping was applied to plain scalars too,** which YAML does not escape: an unquoted value's backslashes are literal, so `C:\\srv` read back as `C:\srv`. Reading now looks at which form the value is in and unescapes only a double-quoted one. The plugin quotes everything a person can influence, so its own data was unaffected, but a property written unquoted by anything else was being rewritten.
- **`set_frontmatter_prop` handed its value to `awk -v`,** which processes escape sequences: a `\"` came back out as a bare quote, and a `\n` became a real newline that split the scalar and injected a second YAML key. The value now travels through the environment, and newlines are stripped.
- **`rebuild_session_md` wrote every value unescaped.** It is the one writer nothing rewrites afterwards, so a quote there left a note broken for the rest of the session rather than for one hop.
- **The helpers did not load under zsh,** which is the shell the session-manager skill is documented to source them from. `BASH_SOURCE` is unset there, so the resolver was looked for in the caller's directory and silently never defined. Both files now fall back to `$0`.
- **Seeding a name at registration exempted every named session from the ghost-folder check,** which treated a non-empty `session_name` as proof that work happened. That inference was sound only while a finished conversation was the only thing that could set it. Since hooks never delete a folder, kb-lint is the only collector, so a failed launch would have accumulated permanently. The check no longer looks at the name; the transcript, the documents, the end time and the summary decide.
- **The start hook assumed the session's folder was under today's date** instead of resolving it, which the other three hooks already do. A `/clear` after midnight, or a reused `--session-id`, therefore checked a path that was not the session's folder: the "write only when absent" guard saw nothing, a second blank note appeared, and the note holding the real metadata was orphaned.
- **The one-shot derivation request could be spent without being made.** The stamp was written before the instruction was emitted, so a timeout or a jq failure consumed it, and since `startup` fires once per session id nothing could ask again. It is now written last. The gate also checks that the note has no tags, which the instruction had been asserting without verifying.
- **Declared delegation was recorded in one narrow window.** The launcher's name was resolved only while creating a note, so a session whose note already existed lost the relationship for good: the marker is gone by exit and nothing downstream can rediscover it. A session that is both forked and delegated now records both.
- **A wildcard mapping outranked a more specific exact one,** because specificity counted the trailing `*`. Since `project` decides where distilled knowledge is filed, that filed a whole tree under the wrong domain silently.
- **Two mappings the tool accepted could never match anything**: a prefix with a trailing slash, which is what shell completion produces, and a `*` anywhere but the end. The first is now normalised and the second refused. `--set-domain` without tags failed outright, which was the form the help text and the README both documented.
- **`--set` could overwrite keys with their own validated writers.** Setting the knowledge bank path through it skipped the directory check and left every hook reporting an unconfigured bank; setting the domain map replaced the object with a string, after which every directory resolved to empty with nothing to show why. Both are now refused with a pointer to the right command.
- **The unknown-property preserve loop dropped list values.** It kept only key lines, so an unknown list property survived as a bare null key with every item deleted. That is exactly the preservation ADR-0002 promises. Continuation lines now travel with their key.
- **Person-chosen names reached a `printf '%b'`.** A name containing `\c` truncated the note body and took the `## Transcript` pointer with it, which under the reference-only architecture is the only pointer to the conversation. The lineage section is assembled outside that expansion.
- **`validate_project` matched its argument as a regular expression,** so a legacy basename like `a.x` validated against the domain `a2x`.
- **`PLUGIN_CONFIG_FILE` was not exported** although the functions reading it were, so a child shell resolved every project to empty. `resolve_project.sh` also no longer clobbers a caller's `SCRIPT_DIR`.
- **ccfind showed nothing for an unnamed session** in an unmapped directory, since its label fell back to `project`. It now falls back to the directory the session ran in.
- **`schema_version` is `2.1`** on newly written notes, four properties having been added. Existing notes keep the version they were written with.
- **The regression suite gave false confidence.** It passed with the escaping made a no-op, with the fork detector's hardening removed, and with the terminal rename unscoped. Those three are now covered, along with the review's own findings, taking it from 74 assertions to 104. Two hygiene bugs fixed: one assertion was vacuous because `/tmp` is a symlink on macOS and `find` does not descend it, and the suite left per-session cache files in `/tmp` that could hand a stale path to the next run.

## [2.11.0] - 2026-09-14

### Changed
- **session-manager skill rewritten** against the skill-authoring guidance, 160 lines down to 93 plus a 50-line disclosed reference. The mandatory opening sequence now sits at the top rather than below all the reference material, where it had needed three separate emphatics to overcome its own placement. Its header also claimed "steps 1-4" while listing six, so which steps were mandatory was genuinely ambiguous.
- **Tag canonicalization disclosed** to `tag-canonicalization.md`. Only the tags branch reaches it, so setting a project or summary no longer carries it.
- **Description pruned** from 90 words to 36. It had one branch written five ways, which cost context on every turn without adding a trigger.
- **Leading words** replace restatement: *own* carries the boundary between the four properties the skill writes and the rest that the hooks manage, which had been stated in three places; *preflight* names the opening sequence; *canonical* replaces the prohibition against setting tags directly.
- **Prohibitions turned positive**, four down to zero, since naming a banned behaviour makes it more available rather than less.

### Added
- **A verifiable completion criterion for the terminal rename.** `rename_terminal_window` is best-effort and reports nothing, so a failed rename was silent and the skill could not tell done from not-done. It now reads the label back from Herdr or tmux and confirms it matches.

### Removed
- The Examples and Constraints sections, which restated the command form, the property table and the tag workflow already defined above them.

## [2.10.0] - 2026-09-14

### Fixed
- **Session folders are no longer deleted by a peer session.** `session_resume.sh` cleaned up "ghost" folders through a rendezvous file keyed by `md5(cwd)`. Because that key is shared by every session in a directory while the folder it removed belonged to a single session, any second session resuming or compacting in the same directory deleted a live session's folder. Confirmed collateral across the corpus was six real sessions, one of them 2709 lines and 442 turns, against one confirmed ghost caught. The rendezvous and the `rm -rf` are both gone; no hook deletes a session folder any more. See `docs/adr/0001-hooks-never-delete-session-folders.md`.
- **A lost note is now rebuilt mid-session, not only at session end.** `session_resume.sh` rebuilt only when the whole folder was missing, so a folder that survived as a shell (recreated by a later document write) kept a missing `session.md` for the rest of the session's life, which made the session-manager skill fail against it.
- **`session_end.sh` no longer files a recovered session under today's date with blank metadata.** It read the properties it wanted to preserve out of the very file that was missing, producing notes with empty `date`, `project`, `cwd` and `started_at`. It now reconstructs from the transcript and takes the date from the existing folder. Same fix in `pre_compact.sh`, which could record a compaction boundary into a freshly invented folder.
- **`/clear` no longer discards tags, summary and name.** `session_start.sh` also fires for `clear` with the same session id and rewrote the note unconditionally. It now writes only when the note is absent.
- **Hook timeouts were in the wrong units.** Values of `5000` and `30000` were written as milliseconds, but the field is seconds. Corrected to 5 and 10. Removed from `SessionEnd`, whose 1.5 second budget is fixed by the harness and cannot be raised by a plugin.

### Added
- **Forked sessions are registered.** New `fork` SessionStart matcher routed to `session_start.sh`. Previously a fork fired no matcher at all, so it got no folder at start and `session_end.sh` invented a bare one, which is what made forks look like empty duplicates of a real session.
- **`forked_from` frontmatter property**, derived from the parent's replayed folder marker in the fork's own transcript, and backfilled at session end because the transcript is written asynchronously and the fork-time scan can lose the race.
- **`resolve_session_folder`, `transcript_forked_from` and `rebuild_session_md`** in `skills/common/obsidian_helpers.sh`, shared by the resume, pre-compact and end hooks so all three agree on how a session folder is found and repaired. Timing comes from the transcript's birth time, which is the session's own start even for a fork, whose first records are its parent's replayed history.
- **kb-lint check 6, ghost session folders.** Collecting ghosts moved out of the hooks and into lint, on a signature no live session can match: a note nobody updated, no documents, no end time, older than a day, and a transcript that is absent or never grew. Reports by default and quarantines rather than deletes.

- **Regression suite** at `tests/hook-regression-suite.sh`, 25 cases against a scratch knowledge bank in a temp directory, never the real vault. Covers the failures above directly: a peer resuming in the same directory cannot delete another session's folder, a lost note is rebuilt without being refiled under today, `/clear` preserves tags and summary, a fork records its parent, and unknown frontmatter properties survive the end rewrite. Resolves the plugin from its own location, or from `PLUGIN=` to test an installed copy.

### Changed
- `session_end.sh` now preserves unknown frontmatter properties verbatim instead of rebuilding from a fixed list, so properties written by skills survive a rewrite.

## [2.9.0] - 2026-09-12

### Added
- **Herdr agent name**: Session names now also propagate to the Herdr *agent name* (`herdr agent rename`), not just the pane label. New `rename_herdr_agent()` helper in `skills/common/obsidian_helpers.sh`, called from `rename_terminal_window()`, so both session-manager step 4 and `session_resume.sh` pick it up. The name is sanitized to Herdr's `^[a-z][a-z0-9_-]{0,31}$` rule (lowercased, invalid runs collapsed to `-`, truncated to 32 chars); on `agent_name_taken` it retries once with a pane-id suffix (e.g. `-w2p5`). Best-effort: never fails the caller. Once named, other agents can address the session with `herdr agent prompt|wait|get <name>`.

## [2.8.0] - 2026-07-31

### Added
- **Herdr pane rename**: Session names now propagate to Herdr pane labels, not just tmux windows. New `rename_terminal_window()` helper in `skills/common/obsidian_helpers.sh` detects the environment (`$TMUX_PANE` / `$HERDR_PANE_ID`) and renames whichever container encloses the session — both when nested. Uses `herdr pane rename` over the socket API; resolves the binary via `command -v` with `~/.local/bin` fallback for minimal hook PATHs.

### Changed
- **session-manager step 4 + session_resume.sh**: Both now call the shared `rename_terminal_window()` helper instead of duplicating inline tmux commands.

## [2.7.0] - 2026-04-09

### Added
- **session-recap: Full Recap enforcement**: New "No Shortcuts" section — every recap executes all 5 phases completely. A daily log alone is not a recap.
- **session-recap: Batch Recap**: Guidance for processing multiple sessions chronologically — discover, triage, process per-session with full phases, parallelize independent projects, integrate once at end.
- **kb-lint: Fix step (Step 4)**: After reporting, offer resolution via AskUserQuestion — batch stub creation, alias resolution, template placeholder removal, index drift fix, or skip.
- **kb-lint: `references/fix-guide.md`**: Stub creation templates, classification heuristics, alias resolution, template cleanup details.
- **KB schema: Stub Documents section**: Explains lifecycle (stub → active/deleted), type inference, `> [!stub]` callout convention.

## [2.6.1] - 2026-04-09

### Fixed
- **kb-lint `set -e` incompatibility**: `extract_wikilinks()` uses `grep` which returns exit 1 on files with no WikiLinks, and `resolve_wikilink()` returns 1 for unresolvable links — both expected behaviors for lint but caused silent script exit under `set -e`. Added `|| true` guards in the pipeline and lint script calls.

## [2.6.0] - 2026-04-09

### Added
- **Session-manager AskUserQuestion**: All confirmations and prompts (tag suggestions, ambiguous requests, no-request invocations) use the `AskUserQuestion` tool for proper user input.

### Changed
- **Tmux window rename**: Now runs on every session-manager invocation regardless of user request (tags, summary, etc.), not just when customTitle changes. Disables tmux `automatic-rename` to prevent overwrite.

## [2.5.0] - 2026-04-08

### Changed
- **kb-ingest v1.1.0**: Refactored from single-mode to dual-mode skill (Quick + Study) based on real-world usage. Study mode adds theme-by-theme walkthrough with online research, three-layer KB output (source/digest/learning notes), and optional blog/slack synthesis. All decision points use AskUserQuestion tool. New `study` and `source` document types added to KB schema.

## [2.4.0] - 2026-04-08

### Added
- **Session-manager tag suggestions**: When setting tags, skill reads existing tags from ccfind cache and suggests reusing similar ones (e.g., `rule-forge` → `ruleforge`). Presents a confirmation table with usage counts before setting.
- **Session-manager customTitle auto-sync**: On every invocation, reads `/rename` customTitle from transcript via `read_custom_title()` and auto-sets `session_name` in session.md if missing or different.
- **Tmux window rename**: Session resume hook and session-manager skill rename the tmux window to `session_name`. Uses `$TMUX_PANE` for correct window targeting.
- **`read_custom_title()` helper**: New function in `obsidian_helpers.sh` — reads customTitle from transcript via reverse-scan. Uses cwd hash (not git repo root) matching Claude Code's project directory structure.

### Changed
- **Session folder lookup**: Replaced `find` (330ms on 500+ sessions) with temp file caching across hook lifecycle (<1ms). SessionStart writes path to `/tmp/second-brain-folder-$SESSION_ID`, other hooks read it back. Falls back to glob then mkdir.

### Fixed
- **SessionEnd hook timeout on large KBs**: `find` across 500+ session directories consumed 330ms (22% of 1.5s budget). Glob fallback takes 10ms; temp file takes <1ms.

## [2.3.0] - 2026-04-05

### Added
- **`_meta/index.md`**: Auto-generated content catalog covering all 188 KB documents, organized by project and type. Regenerated after every write operation via `generate_index.sh`.
- **`_meta/log.md`**: Chronological operation log tracking ingests, queries, lint passes, and index rebuilds via `append_kb_log()` in `obsidian_helpers.sh`.
- **`_meta/schema.md`**: Unified KB conventions file consolidating document types, frontmatter requirements, WikiLink standards, naming conventions, and operations reference.
- **kb-ingest skill**: Standalone source ingestion for articles, gists, docs, and URLs outside of Claude Code sessions. Interactive READ → DISCUSS → CREATE → INTEGRATE workflow following the LLM Wiki pattern.
- **kb-lint skill**: Knowledge bank health-check with 5 checks — broken WikiLinks, missing frontmatter, orphan documents, index drift, and stale content. Severity-graded reports at `_meta/lint-report-*.md`.
- **session-recap source detection**: Phase 1.4 scans session.md body sections (`## Generated Artifacts`, `## Plans`, `## Memory Snapshot`) and transcript for ingestible artifacts and references. Phase 2.4 plans which sources to ingest as KB docs.
- **ccfind `Ctrl-R`**: Refresh keybinding reloads session list without reopening fzf popup.

### Changed
- **knowledge-bank-lookup navigation**: "Index or MOC-First" strategy — `_meta/index.md` as fallback for projects without MOCs (CC, supply-opt).
- **knowledge-bank-lookup query write-back**: After high-value lookups, offer to file the synthesis as a KB document via kb-ingest workflow.
- **session-recap Phase 3 priority order**: Expanded from 5 to 7 levels — artifact-derived docs (5-8 WikiLinks) and reference-derived docs (5-8 WikiLinks) inserted at priorities 4-5.
- **session-recap Phase 5**: Added steps 5.2 (regenerate `_meta/index.md`) and 5.3 (append operation log).
- **Tiered WikiLink minimums**: Session-derived docs keep 10-15; ingested/artifact/reference docs require 5-8. `count_wikilinks.sh` accepts optional `min-links` parameter.

### Notes
- Inspired by [Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
- All changes are backward-compatible with existing KB documents

## [2.2.0] - 2026-03-22

### Changed
- **Reference-only session architecture**: Hooks no longer copy transcripts, agents, or plans into `segment-*` directories. `session.md` stores a `transcript_source` frontmatter property pointing to the original transcript at `~/.claude/projects/`. Eliminates ~99.8% of `_sessions/` storage overhead.
- **SessionEnd performance fix**: Removed 3 full-file grep operations (agents, plans, customTitle) that exceeded the 1.5s `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` cap. CustomTitle extraction now uses `tail -r` reverse-scan (14ms vs 322ms on 42MB transcripts).
- **PreCompact hook**: Replaced segment copying with a `compaction-points.txt` sidecar file that records line count + timestamp per compaction boundary.
- **session-recap Phase 1.1**: Reads `transcript_source` from session.md frontmatter first; falls back to `segment-*/transcript.jsonl` walking for old sessions.
- **SessionStart matchers**: Added `clear` and `compact` matchers for `/clear` and post-compaction events.

### Added
- **ccfind `--by-name` / `Ctrl-N`**: Browse only named sessions (sessions with `session_name` set via `/rename`). Replaces the old `--by-task-tag` mode.

### Removed
- **`task_tag` property**: Merged into `session_name` + `tags`. In practice, `task_tag` was identical to `session_name` in most sessions (one task = one session). Use `tags` for grouping related sessions.
- **ccfind `--by-task-tag` / `--task-tags`**: Replaced by `--by-name` / `Ctrl-N`.

### Fixed
- **SessionEnd hook cancelled**: Root-caused the "Hook cancelled" error — `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` (default 1.5s) silently caps per-hook `timeout` settings in hooks.json.

## [2.1.0] - 2026-03-06

### Added
- **Auto memory snapshot**: SessionEnd hook copies `~/.claude/projects/{hash}/memory/` to session folder, with `## Memory Snapshot` section in session.md body
- **Session-manager skill**: `project` is now a customizable property (was hook-only); skill shows current session info on every invocation
- **ccfind**: Shell + fzf tool for searching and resuming sessions by metadata (`--by-tag`, `--by-task-tag`, keybindings for resume and open docs)

### Changed
- **session-recap v3.1.0**: Reads session.md as hub for metadata and content discovery; adds `session-folder` back-reference to all recap-created KB docs

### Removed
- **`generated_artifacts` property**: Dead placeholder — initialized but never populated

## [2.0.0] - 2026-01-12

### Added
- **Centralized session management**: Hooks for SessionStart, SessionEnd, PreCompact, and Resume
- **session.md**: Obsidian hub note with YAML frontmatter replaces `session-info.json` as single source of truth
- **Obsidian CLI integration**: All session note creation and property updates via CLI
- **Session-manager skill**: Tag sessions with `task_tag`, `tags`, and `summary` via Obsidian CLI
- **Dataview MOC**: `_sessions/MOC-Sessions.md` for task-first session browsing
- **Ghost cleanup**: Resume hook detects and removes ghost folders created by startup matcher firing during resume
- **hookSpecificOutput schema**: SessionStart hooks inject docs path into system prompt

### Fixed
- Obsidian datetime format: removed `Z` suffix for compatibility
- Empty list placeholders: skip `type="list"` with empty value to avoid `[""]`
- Obsidian CLI stdout pollution: redirect writes, filter loading messages on reads
- Obsidian app launches on CLI use: hide window via osascript after create

## [1.0.0] - 2026-01-08

### Added
- **session-recap skill**: Distill Claude Code sessions into knowledge bank documents (concepts, components, best practices, reflections, daily logs)
- **knowledge-bank-lookup skill**: Retrieve relevant context from knowledge bank with reflections-first strategy and WikiLink DFS traversal
- **Plugin configuration**: `~/.claude/plugins/config/second-brain/config.json` for knowledge bank path
- **Knowledge bank structure**: Projects, daily logs, sessions, index with Obsidian vault support

---

## Skill Changelogs

| Skill | Changelog |
|-------|-----------|
| session-recap | `skills/session-recap/CHANGELOG.md` |
| knowledge-bank-lookup | `skills/knowledge-bank-lookup/CHANGELOG.md` |
