---
status: accepted
date: 2026-10-27
implementation: 2.21.0
---

# A recap session ends itself once its recap is done

A recap session now ends itself. Once the skill has written `recap_status: done`, the session has finished
its turn, two minutes pass with no new turn in it, and its prompt box is empty or holds only dim ghost text,
`recap_exit_watch.sh` types `/exit` into it through Herdr. `recap_child.sh` starts the watcher beside `claude`,
behind the launcher's own Herdr gate, and stops it on the way out. Every check that fails leaves the session
open, as before, with the reason in the subject's `recap.log`.

A recap session is interactive on purpose: a person can watch it and step in, and
[ADR-0007](0007-a-new-domain-is-proposed-by-the-recap-created-on-approval.md) asks its one question there.
Nothing ever ended one, so a finished recap held about 2.5 GiB until someone closed its pane. On 2026-10-27
the host ran out of memory with 24 recap sessions open, 34.1 GiB between them.
[ADR-0009](0009-a-launcher-can-declare-its-delegate-exempt-from-the-automatic-recap.md) stopped recapping
ticket sessions, which all 24 were, but recaps of the owner's own sessions stayed open as well, one of them
for 66 hours.

## Considered Options

**Run the recap in print mode.** Rejected. `claude -p` exits by itself, but it leaves no pane to step into,
and ADR-0007's question, the one prompt the skill is allowed, could not be answered.

**A Stop hook in the recap session.** Rejected. It would run at the end of every turn of every session to
serve recap sessions alone, for a decision that needs nothing from inside the session.

**Turn Claude Code's prompt suggestions off in the recap session, so an idle box is truly empty.** Rejected.
The debrief mod offers its first `me` step in the same box as dim ghost text, so the box has to be read with
its attributes either way. The ticket dispatcher already reads it so before it types `/exit` into a ticket
session, and its check is ported as it stands.

**Close the pane as well.** Not done. The memory is the session's; an idle shell costs a few megabytes, and a
reused pane is the owner's own.

## Consequences

The watcher ends a recap session the way the ticket dispatcher ends a ticket session, with `/exit` into a
session Herdr shows visibly idle at a box that takes it cleanly, so there is still one way for a session to
end. `done` is the only trigger, and ADR-0007's question is asked while the status is `running`, so a recap
waiting on a person is never ended.

A person keeps a recap session by working in it. A turn started during the grace makes the session theirs for
good, and a line typed but not sent keeps the box from taking `/exit`. A re-request during the grace keeps it
open too.

Outside Herdr nothing changes. There is nothing to type `/exit` through, so no watcher starts, and a recap run
from a pasted command stays open until its person closes it.

The pane prints one line when the session ends, naming the subject, its status and its log, because a session
that ended itself would otherwise leave a person at a bare shell prompt.
