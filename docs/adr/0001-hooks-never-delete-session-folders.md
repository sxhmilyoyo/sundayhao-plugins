---
status: accepted
date: 2026-09-14
---

# Hooks never delete session folders

Hooks register and repair session notes; they never delete a session folder. A rendezvous keyed by
working directory used to clean ghost folders at resume time, but the key is shared by every session
in that directory while the folder it removes belongs to one session, so it destroyed live work.
Ghost folders are now swept by the lint skill, on a signature no live session can match: a note
nobody updated, an empty docs directory, an age past a day, and a transcript that never grew.

## Considered Options

**Guard the delete** with a freshness check on the key, a pristine-folder check, and a move to
quarantine instead of a recursive delete. Rejected. It keeps a sweeping delete on live data inside a
race, and buys only that a ghost is cleaned seconds earlier than a lint pass would clean it.

**Remove ghost cleanup altogether.** Rejected. Ghost folders were verified directly with hook debug
dumps in March 2026, so something has to collect them; lint is the safe place for that, because it
runs on demand and can report before it removes.

## Consequences

Ghost folders stay visible in the vault until a lint pass runs. That is deliberate. A folder nobody
wanted costs a line in a report; a folder someone needed costs a day of work.

Anyone tempted to reinstate cleanup inside a hook should weigh the evidence first. The mechanism's
confirmed collateral was six real sessions, against one confirmed catch. Ghosts leave almost no
trace, so treat that catch count as a floor rather than a measurement, and treat the collateral count
as the reason the trade was still wrong.
