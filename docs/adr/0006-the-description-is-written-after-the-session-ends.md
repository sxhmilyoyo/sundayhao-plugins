---
status: accepted
date: 2026-09-15
implementation: 2.13.0
---

# A session's description is written after it ends, not asked for when it starts

A session note's project, tags and summary say what the work was about, and nothing at launch knows
that. Version 2.12.0 asked the model instead: the SessionStart hook injected an instruction to run the
session-manager skill in automatic mode and stamped the note so it would ask only once. That request is
removed. The recap that already runs after a session ends now writes all three, reading the whole
conversation rather than guessing from a name.

The injected request did not work, and could not. A hook's `additionalContext` is placed in the context
before the first user message, but nothing makes the model act on it: measured on the first real session
to carry the instruction, five user prompts and thirty-nine assistant turns produced no tags, no
`property:set`, and no skill invocation, while the stamp recorded that the request had been made. Even
when a model does comply, the work competes with the user's first request for the same turn, and the
alternative of forcing it earlier is worse: a derivation that runs before the user has said anything has
no more evidence than the hook had. Replaying tag derivation mechanically over 238 named sessions scored
0.72 precision and 0.48 recall, which is the ceiling a session name supports.

Registration keeps everything it can read off the environment: the folder, the note, the session id and
name, the git branch, the directory's domain, and for a fork or a delegate the lineage and the inherited
description. Those are facts at launch, not descriptions of work.

## Considered Options

**Trigger the skill from `UserPromptSubmit` instead.** Rejected. It fires on every prompt, so it needs a
one-shot gate, and the gate has to distinguish "asked" from "done" without being able to see whether the
model complied. A per-prompt hook also costs 55 to 81 ms on every prompt for the life of every session,
measured across three gating shapes, to serve a one-time need.

**Return `initialUserMessage` from the hook** so the derivation is the session's first turn. Rejected. It
is documented for print mode, it would displace the user's own first message in an interactive session,
and it still derives from the name alone.

**Keep the start-time request as well, as a first guess the recap refines.** Rejected. Two writers for
one property, and the guess is the one made with the least evidence. The value of writing early was that
tags existed while the session ran; nothing consumes them during the session.

## Consequences

This narrows [ADR-0002](0002-recap-status-lives-on-the-session-note.md): the recap writes the subject's
`project`, `tags` and `summary` in addition to its own `recap_` properties. Ownership is now stated by
stage rather than by writer. The hooks seed what registration can see and never overwrite. The
session-manager skill is the only writer while a session runs. The recap is the only writer after it
ends, and it overwrites, because by then it has the most context anyone will ever have about that
session.

A session's description therefore arrives minutes to hours after the work, and only for sessions that
are recapped. A session below the recap threshold, one that ended while the feature was off, and one
whose Claude crashed are never described unless a person asks. Until the recap can be launched from the
end hook, a description requires pasting the command the start-of-session notice prints.

The recap becomes the only place a domain is decided for work in an unmapped directory, so it must be
able to launch without one: it infers the domain from the conversation, and when nothing in the bank's
domain set fits, it writes tags and summary, leaves the project empty, and marks the subject failed so
the notice asks a person. Recapping is not blocked on a value only recapping can supply.

Tags are canonicalized against the vault as before. A recap may coin a tag the vault has never seen only
when the conversation gives repeated evidence for it, and otherwise records it as a proposal, because an
unattended writer that coins freely is how a shared vocabulary drifts.

The `metadata_requested_at` property stays on the notes that already carry it. It is inert, it records
that a request was made on a day when one was, and removing it would be a delete for tidiness.
