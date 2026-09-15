# Second Brain

A Claude Code plugin that records each coding session as a durable note in a knowledge bank, and files
the working documents produced during that session alongside it.

## Language

### Sessions

**Session**:
One conversation with Claude Code, identified by a session id that the harness assigns.
_Avoid_: chat, thread, run

**Session folder**:
The dated container holding one session's note and its working documents.
_Avoid_: session dir, cubby, bucket

**Session note**:
The record of a single session, carrying its identity, timing, project, name, tags and summary.
_Avoid_: session file, metadata file, frontmatter

**Registration**:
Creating a session's folder and note at the moment the session begins, so later stages have something
to update rather than invent.
_Avoid_: init, bootstrap, provisioning

### Session lineage

**Fork session**:
A session whose conversation continues an existing one under a new session id. A fork is a real
session that deserves its own note, not an artifact to be discarded.
_Avoid_: duplicate session, copy, clone

**Parent session**:
The session a fork continues. Recorded on the fork so lineage can be followed in either direction.
_Avoid_: origin, source session, root

**Ghost folder**:
A folder registered for a session id that never became a conversation, recognised by a note nobody
ever updated and a transcript that never grew. Distinct from a fork, which does become a
conversation, and from a stub, which is created after the fact.
_Avoid_: phantom, orphan, empty session

**End stub**:
A session folder created only at session end, because no note was found to update. It carries an end
time but no start metadata, which is what makes it look like an empty duplicate of a real session. A
stub means registration was missed or the note was lost, never that the conversation was empty.
_Avoid_: empty duplicate, orphan folder

### Recording stages

**Resume**:
Continuing an existing session under its own id. Distinct from a fork, which mints a new id.
_Avoid_: reopen, restore, continue

**Compaction boundary**:
The point at which a session's conversation was summarised to reclaim context, recorded so the
session's history can be read in segments.
_Avoid_: compact point, checkpoint, truncation

### Recap

**Recap session**:
A session whose only purpose is to produce the recap of another session. It is a real session and ends
like any other; it is never the session it describes.
_Avoid_: separate session, child session, recap child, background recap

**Recap**:
The knowledge-bank documents distilled from one subject session: its daily log, and any concepts,
components, practices and reflections drawn from it.
_Avoid_: summary, digest, write-up, session notes

**Subject session**:
The session a recap describes. It is the subject before, during and after the recap, and it never
produces its own recap.
_Avoid_: recapped session, target session, source session, original session, parent session

**Recap status**:
The recorded outcome of recapping a subject session, carried by the subject's own session note.
_Avoid_: recap marker, recap flag, done marker, sidecar

**Stalled recap**:
A recap whose status has stopped advancing without being marked failed: requested but never started,
or running far longer than a recap takes. A judgement made from elapsed time, not a stored state.
_Avoid_: stuck, hung, timed out, zombie, orphaned recap

**Exempt session**:
A session that is deliberately never recapped: a recap session itself, or a session too small to carry
knowledge worth distilling. Exemption is recorded, so an exempt session is never mistaken for a missed one.
_Avoid_: skipped session, trivial session, ignored session, noise
