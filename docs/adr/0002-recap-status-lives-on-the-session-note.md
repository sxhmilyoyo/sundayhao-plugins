---
status: accepted
date: 2026-09-14
implementation: 2.13.0
---

# Recap status lives on the session note

The recap skill's 3.1.0 changelog made the session note read-only for recap, so that recap never had to
coordinate with the hooks that rewrite the note. We now let the recap write to the note, but only
properties it owns, all prefixed `recap_` (`recap_status`, `recapped_at`), because the outcome of a recap
has to be visible where sessions are already looked at: the note's properties in Obsidian, ccfind's cache,
and the SessionEnd hook that decides whether to request a recap at all.

## Considered Options

**A sidecar file in the session folder** (`recap.status`). Rejected. It keeps the read-only rule intact
and needs no hook change, but Obsidian hides non-Markdown files, ccfind reads only note frontmatter, and
a "not yet recapped" listing would need a second reader for a second format.

**Both**: a sidecar for machine state and a single `recapped_at` property for people. Rejected. Two
sources of truth for one fact, and the failure states would be the ones hidden from view.

## Consequences

The read-only rule is narrowed, not dropped: recap writes `recap_`-prefixed properties and nothing else,
hooks own everything else, and the session-manager skill leaves `recap_` properties alone. The
SessionEnd rewrite must preserve properties it does not know about, which it now does.

Narrowed again by [ADR-0006](0006-the-description-is-written-after-the-session-ends.md): the recap also
writes the subject session's `project`, `tags` and `summary`, which no longer have a writer at session
start. Ownership now reads by stage rather than by writer. Hooks seed at registration, the
session-manager skill writes while a session runs, and the recap writes once it has ended.

`recap_status` takes one of `requested`, `running`, `done`, `failed`, `exempt`, and each value has exactly
one writer: the SessionEnd hook, the launcher once the recap session starts, the recap skill's final
phase, the launcher's exit check, and the SessionEnd hook again for sessions that are never recapped.
The hook requests a recap only when the property is empty, so repeated exits after a resume cannot
request twice. A stalled recap is a judgement from elapsed time, never a stored value. A retry resumes:
it inventories documents already carrying the subject's `session-folder` and updates them in place;
recap never deletes knowledge-bank documents.
