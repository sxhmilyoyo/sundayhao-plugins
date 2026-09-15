---
status: accepted
date: 2026-09-14
---

# Delegation is declared, not detected

A delegated session learns which session launched it from a marker its launcher sets in the
environment. Nothing infers the relationship afterwards. A launcher that sets no marker produces an
ordinary session with no lineage, which is preferred over a guess.

[ADR-0003](0003-recap-sessions-are-registered-guarded-by-env.md) already established the pattern for the
one delegated session the plugin launches itself, passing the subject's folder to a recap session in its
environment and letting the ordinary SessionStart hook record the relationship. This decision
generalises the mechanism to any launched session, under a marker naming the launching session rather
than a subject, because a recap's relation to its subject is not delegation: the glossary makes a recap
session's counterpart a subject session and explicitly refuses to call it a parent.

Detection looks easier than it is. The only ambient clue is the process chain, and the launcher that
most wants recording is the one that deliberately detaches, so it leaves no chain to walk. The
identifier that appears to solve this does not, because the session id in a hook's environment is always
that hook's own session, so an inherited value is overwritten before any hook can read it. A custom
variable, by contrast, was verified to survive the launch chain into a detached grandchild.

Declaring also draws the boundary in the right place. A daemon on this machine has produced thousands of
child sessions that no session launched, which detection would have to recognise and reject by name,
while a declaration excludes them for free by never being set.

## Considered Options

**Have the launcher write the delegate's note before starting it.** Rejected. It is the only option that
works whether or not the child's hooks run, but it writes a folder for a session that has not begun, so
every failed launch leaves exactly the ghost folder that
[ADR-0001](0001-hooks-never-delete-session-folders.md) exists to explain. A session that never starts
should leave nothing behind.

**Infer the launcher from the process tree.** Rejected. Fragile for detached launches, which are the
common case, and it needs a second lookup to turn a process into a session.

**One marker for every kind of launch.** Rejected. Collapsing a recap's subject and a delegate's
launcher into one property would force every reader to branch on kind anyway, and it would overwrite a
distinction the glossary keeps deliberately.

## Consequences

The marker travels on the launched command itself, never on the pane or shell that hosts it. A terminal
manager's environment option adds the variable to the pane's root shell, so every later session opened in
that pane would inherit a launcher that never launched it, and be recorded as delegated. As defence in
depth, hooks honour the marker only when the session's start event is a genuine startup, not a resume,
clear or compaction.

Any tool that launches a session and wants lineage recorded has to opt in, so the plugin ships one
helper that sets the marker and names the delegate. A launch that bypasses the helper is silently
unrecorded, which is the same outcome as before this decision, and is why it is acceptable.

Registration itself stays where it already is, in the session's own hooks, so nothing new has to run
inside a session whose hooks may not fire. The consequence is a boundary rather than a failure: a
delegate launched in a mode without hooks has no note, exactly as such sessions have none today.
