---
status: accepted
date: 2026-11-03
implementation: 2.24.0
amended: 2026-11-03, in 2.24.1 (the hooks' guard compares process groups)
---

# A session declares its folder on the terminal that hosts it

A session's own hooks keep one hc label on the hc terminal that hosts it,
`second-brain.session=<absolute path of the session folder on that machine>`, and the Herdr app's Files panel
shows that folder from the label and from nothing else. `session_start.sh` sets it at every startup, `/clear`
and fork, and `session_resume.sh` at every resume and compaction; `/clear` keeps the session id, so it sets
the same value again. `session_end.sh` removes it in hc's `key=` form at a real end, right after its recap
stamp. The `clear` and `resume` reasons leave it, because the end hook already treats them as non-endings and
the SessionStart that follows each sets it again. The reader is the `session-folder` mod this plugin ships: it
takes the label off the focused pane's own terminal, and a terminal without one gets no Session section.

A session's plans, reviews and handoffs land in its session folder, and nothing outside the session could say
which folder that was. Matching the knowledge bank against the pane's working directory is ambiguous: six
sessions shared one working directory in three days. So the decision follows
[ADR-0005](0005-delegation-is-declared-not-detected.md). The session declares the fact, outside an hc terminal
nothing is set, and a consumer never guesses.

The value is machine-local. It is a path on the machine whose core hosts the terminal, so a consumer reads the
folder there, through hc, and a session in a space on another machine is listed and read on that machine. The
key sits in a `second-brain.*` namespace beside Herdr's `herdr.*` and ccfind's `ccfind.*`, and this one label
is the whole contract.

Both ends are guarded, so that the label means what it says. A nested `claude`, such as a `claude -p` run from
a Bash tool, inherits `$HC_TERMINAL_ID` too; it would relabel the host with its own folder and then take the
host's label away at its own end, and nested runs like that happened three times in sixty days. So when
`$CLAUDE_PID` is set, the hooks write only if that claude is in the terminal's foreground process group, the
group hc's `foreground.pid` names. A Bash-tool command runs in a session of its own with no terminal, so a
claude it starts never is. Without `$CLAUDE_PID` there is nothing to compare, so they write as before. On the
reading side, a label outlives a session that dies without its end hook, so the panel trusts the label only
while the terminal's foreground program is `claude`. Both guards ask whether claude is what runs in front: the
hooks by its process group, the panel by the foreground program's name.

## Considered Options

**Find the session whose working directory matches the pane.** Rejected. Six sessions shared one working
directory in three days, and a guess shown as the session's folder is worse than no section at all.

**Publish the session id and let each consumer find the folder.** Rejected. Every consumer would then have to
resolve the knowledge-bank path itself, on every machine, repeating work the plugin already does.

**Infer the session from the terminal's process.** Rejected. Fragile, and it would work only on the Mac.

**A standalone hook in `~/.claude/hooks`.** Rejected. The plugin owns the session folder and already
integrates with the Herdr app, and one plugin release reaches both machines, while a separate script would be
two installs to keep in step.

**Trust the agent status the app already reports, `program.agent` or `status`, rather than the foreground.**
Rejected. Sampled every 100 ms in the app, both keep a dead agent's last report, still agent and idle 35 s
after a SIGKILL left zsh in front, and neither is true for a fresh claude in its first 1.5 s. Only
`foreground` followed the crash, within a second, and it is the same signal the hooks' guard uses.

**Compare the foreground with `$CLAUDE_PID` itself.** Rejected after shipping in 2.24.0. hc's
`foreground.pid` is the foreground group's id, and claude does not always lead that group: on the clouddesk,
toolbox starts Claude Code as a shim that runs a wrapper that runs it, with no `exec` at any step, so hc
reported the shim and the comparison refused every session there. Amended to the group comparison in 2.24.1.

**Remove the label first thing in the end hook.** Rejected. Removal costs milliseconds, and its only slow case
is a core that is down or restarting, when a stale label costs nothing because the Herdr app, a client of that
same core, shows nothing either. Ahead of the recap stamp, that case would risk the one silent failure the end
hook exists to prevent, so the removal runs right after the stamp.

## Consequences

A claude run by a wrapper that does not `exec` it stays in the wrapper's foreground job, and so in its group,
and is labelled like any other: toolbox's chain, and `recap_child.sh`'s claude too. The panel still trusts a
label only while the foreground program is named `claude`, so under a wrapper led by `bash`, as
`recap_child.sh` is, the session is labelled but not shown. What claude itself starts outside a Bash tool, its
MCP servers say, shares the group as well, so a claude started from there would pass the hooks' guard; none is,
today.

A crash leaves the label on the terminal, but the panel ignores it while anything other than claude is in
front, and the next session started there sets its own. A person can clear one by hand with
`hc label <terminal> second-brain.session=`.

The key is a contract between two halves that version together: the hooks in this plugin and the mod shipped
from `tools/herdr-app/mods/session-folder/`, which is installed by copy. Renaming or reshaping it means
changing both, on every machine, at once, which is why it is recorded here.

Each SessionStart pays one hc call, and each real SessionEnd one more, after its stamp. A call is bounded at
about half a second, the foreground check included, because a core that is down keeps hc waiting for seconds
and a hook over its budget is cancelled. Measured, a call takes 8–17 ms on the Linux host and 55–75 ms on the
Mac.

Any other consumer can read the label without new plumbing; the Files panel is the first.
