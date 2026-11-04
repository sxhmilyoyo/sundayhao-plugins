---
status: accepted
date: 2026-11-04
implementation: 2.25.0
---

# The Herdr app is driven through hc, and a recap that cannot reuse its pane is a worker

The recap launcher, the recap's exit watcher and the delegate launcher gated on the Herdr TUI alone:
`HERDR_ENV=1`, a pane id and the `herdr` binary. A Herdr app pane has none of them. It is an hc terminal,
`HC_TERMINAL_ID` and the `hc` binary, and the app's window runs on another machine, so nothing on this host
can split one of its panes. In app panes `auto_recap: on` degraded to `notify` without a word (the first
subject left `requested` that way was 43350a3c, on 2026-11-02), the manual launcher printed a command to
paste, no recap session ended itself, and a delegate was a pasted command too.

Each terminal host (GLOSSARY.md) now has its own driver and the same rule. `terminal_host` names the host
from the variables each one sets, the TUI first, then the app, else none; nothing is inferred from which
binaries are installed, because this machine has both. Under the app the recap is typed into the pane you
left with `hc send` when that pane's shell is free, which `hc get` shows as the foreground process being the
pane's root shell; otherwise it runs as an hc worker, a terminal with no pane, started with
`hc run --bg --no-notify --outlive-parent`, listed in the window's agents sidebar and opened in peek from
there. The exit watcher runs its five steps through hc: `hc wait` for the turn to end, `hc get` polled
through the grace, `hc read` for the box, and `/exit` typed as key presses with `hc keys`. A delegate is an
hc worker too, but an hc child of the launching pane with hc's notes on and hc's reach line,
`Report with hc send <parent> when done or stuck.`, appended to its prompt.

## Considered Options

**One driver behind one interface.** Rejected. `herdr agent prompt`, `pane process-info` and
`agent read --format ansi` have no one-to-one hc twin, so an interface would have hidden the two differences
that matter: hc reads the box as plain text, and hc has no wait for "working".

**`hc send "/exit"` to end the session.** Rejected on measurement (2026-11-03). hc wraps text sent to a
program that reports status in its `<hc from="…">` tag, so the session received a prompt that said `/exit`
and started a turn. Key presses with `hc keys` reach the command menu, and the SessionEnd hook runs.

**`hc kill` to end the session.** Rejected on measurement. The program ends but the SessionEnd hook does not
run: the note keeps an empty `ended_at`, and nothing records that the recap's own session ended.

**Split a pane from here.** Not possible. The window is on the Mac; the clouddesk has `hc` and no
`herdr-app`. A worker without a pane was confirmed visible in the window's agents sidebar before this was
built.

**Read the box with its attributes, as under the TUI.** Not possible: `hc read` is text only. So under the
app `/exit` goes only into a box that is exactly empty (the pointer, alone or with the no-break space Claude
Code draws after it, which is how `hc read` gives an empty box back), and the recap session starts with Claude Code's own
prompt suggestions off: `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` on its command, the variable rather than
the `promptSuggestionEnabled` key, because the variable wins over the key and on a third-party provider it is
the only switch that turns suggestions on at all.
[ADR-0010](0010-a-recap-session-ends-itself-once-its-recap-is-done.md)
rejected that switch for the TUI, because the debrief mod's `go ahead` draft needs the attribute read
anyway. Under the app that draft reads as text, and the suggestion variable does not reach it: on 2026-11-04
a draft offered after a recap's first turn was still in the box after its last turn and held the done recap
open, as one had held t43. So the app's recap session also starts with the debrief plugin off, through a
`--settings` that names that one plugin; second-brain's hooks stay on, which is what registers the session
([ADR-0003](0003-recap-sessions-are-registered-guarded-by-env.md)).

**Make debrief draft less instead.** Not enough alone. Drafting only `me, on your word` steps and dropping a
stale offer at the next turn would still leave open any recap whose last Debrief holds such a step.

## Consequences

A recap in the app behaves as in the TUI except where hc differs. A recap that could not reuse its pane is a
worker in the agents sidebar, not a split. A prompt box with any text in it keeps a done recap's session
open, and in the app that text is a person's, since the recap session runs with neither suggestions nor
debrief. That names a sibling plugin inside second-brain: a debrief installed from another marketplace keeps
its draft. The recap worker types no notes into the pane you left, because a note
typed into a shell prompt runs as a command, while a delegate's notes stay on, because its parent is a
session that asked for it. Closing the pane you left does not end a recap or a delegate that outlived it.
The TUI path and the no-host path are unchanged, and `recap.log` names the host's object: `reusing terminal
t8`, `started … in hc terminal t77`, `typing /exit into t77 as key presses`.
