---
status: accepted
date: 2026-11-11
implementation: 2.26.0
---

# A launcher can defer its delegates' recaps to one group recap

A launcher can declare that the sessions it starts belong to a recap group, by setting
`SECOND_BRAIN_RECAP_GROUP=<key>` in each launched session's environment. The start hook records `recap_group`
on the note at a genuine startup, and every exit of such a session stamps `deferred`, a sixth recap status,
and starts nothing. When the launcher says the group is complete, by calling one command with the key, one
recap session takes every member that has ended as its subjects and distils one set of documents from them
together: a group recap. Each member's note still receives its own description and `done`.

The case is again the ticket dispatcher. [ADR-0009](0009-a-launcher-can-declare-its-delegate-exempt-from-the-automatic-recap.md)
made its sessions exempt, after the host ran out of memory with 24 recap sessions open, on the ground that
the tickets already record the work. The owner had wanted the recaps postponed, not dropped: nothing at a
ticket session's exit, and one recap once every ticket under a spec is closed. On 2026-11-11, 451 notes
carried `recap_exempt: launcher`, the dispatcher's standing sessions among them, and nothing automatic would
ever recap one. A full recap takes 43 minutes at the median, over 151 recap logs, so one recap for each
ticket session, at about 28 sessions a day, is about 20 hours of recap work a day.

## Considered Options

**One full recap per session, from a queue.** Rejected. The sessions of one group are slices of one piece of
work, each outcome already sits on its ticket, and a pattern across sessions, which is what a reflection
exists to record, is visible only to a recap that reads them together.

**Keep `exempt` and add the key.** Rejected. A deferred note would read exactly as a session too small to
recap, and "exempt" would stop meaning never. ADR-0009 refused one word meaning two things on the same note,
and held that a session that says no must record that no. The same holds for a session that says later.

**Stamp `requested` at exit and have the notice skip keyed notes.** Rejected for the same reason: `requested`
would mean both start now and wait for the group.

**Have the launcher pass a roster of session ids when the group is complete, with no key at launch.**
Rejected. A note would never name its group. Declared at launch and read off the note is the pattern of
[ADR-0003](0003-recap-sessions-are-registered-guarded-by-env.md),
[ADR-0005](0005-delegation-is-declared-not-detected.md) and ADR-0009.

**Have the launcher start and supervise the recap session itself.** Rejected. The claim and the word that the
recap is done would then come from the model, and the launcher's package would carry a copy of the recap's
lifecycle. Here the status writer keeps both in code.

**Take the completion once.** Rejected. A recap that failed to start, or died, would wait for a person. The
command is idempotent instead, so its caller repeats it until it answers that the group is settled.

**A model run for each member's transcript.** Rejected for the per-member step. A ticket session's transcript
is 5.6 MB at the median, and a digest made by `parse_transcript.sh` is 8 to 23 KB in one to three seconds.
The recap session reads digests, and opens a transcript only where a digest shows errors, rework or an ask.

## Consequences

`recap_status` takes six values. The end hook writes `deferred`; the group command writes it for a member
that ended without its end hook; the claim of a group run moves it to `running`. A member under five
assistant records is `exempt` like any session, and a member that grows after its recap goes back to
`deferred`. The notice never lists a deferred session.

The exemption of ADR-0009 stays, for a launcher that wants no recap at all. A note that carries both
declarations is deferred, which lets a launcher send both while an older plugin is still installed.

A group recap can run more than once for a key. A run takes the members that have ended and are not yet
done; a later one, for a member that ended late or joined when the group was completed again, updates the
group's documents in place, as a retry does
([ADR-0002](0002-recap-status-lives-on-the-session-note.md)). The first run waits for members still alive,
at most an hour after the completion.

A member whose transcript is missing or cannot be read is marked `failed` with its reason and from then on
does not wait: the group settles without it, the command's line says how many such members there are, and a
member whose transcript can be read again waits again. The run records those members, with name, folder and
reason, in a file that the group's manifest names, and the group's daily log entry names them from it,
because the start-of-session notice reaches only the fourteen newest date folders and a group spans weeks; a
later run rewrites the file and the entry's line, so a member recapped after all drops out of both, and a
group whose every member is unreadable starts no session and writes no entry, with the command's line and
its log for its record.

A member has ended when its end hook stamped it, or when Claude Code's session registry shows no live
process for its id. The registry is not documented, so one that cannot be read means alive: the failure is a
wait, never a recap of a transcript still being written.

The command answers by exit code, settled, in progress or needs a person, and sits at one fixed path under
the plugin's config folder, which the start hook keeps current. The launcher knows that path and those three
codes, and nothing of the vault. Where the path is missing no deferred session exists either.

A group recap asks the one question of
[ADR-0007](0007-a-new-domain-is-proposed-by-the-recap-created-on-approval.md) in its own session, as any
recap does. A run that has been in progress over three hours answers that it needs a person, which is how
an unattended question, or a hang, reaches one.

The skill's rule against one daily log for many sessions now holds for a batch only. The glossary gains
deferred session, recap group and group recap, in CONTEXT.md and GLOSSARY.md.

A group recap starts only where the terminal host can start a session from outside a terminal, which today
is the Herdr app. Anywhere else the command says it needs a person and gives the command to run.
