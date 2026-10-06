# Glossary

Canonical vocabulary for the second-brain plugin. Code, docs and ADRs use these terms;
when a term here conflicts with usage elsewhere, this file wins and the other text is stale.

## Domain

A knowledge-bank filing area, one folder under `projects/` in the vault. The fixed set of
domains is the single source of truth every consumer validates against. A domain is an area
of work (`a2x`, `cc`), never a repository, directory or component — those are tags.

## Project (property)

The frontmatter property on a session note that names the [[#Domain]] the session's work
belongs to. Kept as `project` for continuity even though its value is a domain. Empty means
unresolved: visibly missing rather than quietly invented.

## Proposed domain

A domain that does not yet exist, derived by a recap from the session it is recapping, put
to a person for approval before anything is created or filed under it. Only a person's
approval turns a proposed domain into a [[#Domain]].

## Subject

The session a recap is about: the one whose transcript is read and whose note receives the
description (`project`, `tags`, `summary`) and final `recap_status`.

## Recap session

A dedicated session, started by the launcher, that recaps exactly one [[#Subject]] (or a
batch of them). Registered by `recap_of` on its own note; never recapped itself.

## Reflection

A backward-looking record of how a [[#Subject]]'s work went — what worked, what didn't,
what failed and why — written by a recap and filed in the knowledge bank for later pattern
mining. A reflection records; it never proposes. Suggesting a change to the environment is
a [[#Proposed improvement]], produced beside the reflection, not inside it.

## Proposed improvement

A change to the agent's environment — a tool, check, steering file or structure — derived
by a recap from evidence in the [[#Subject]]'s transcript and put to a person for approval
before anything is changed. It names a concrete target and carries a severity; only a
person's approval turns a proposed improvement into a change.

## Decode

Re-explaining a stretch of agent work to the person supervising it, grounded in that
session's own evidence rather than the general case. The wdym skill performs decodes.

## Agent output

What a [[#Decode]] explains: the agent's prose conclusions, the raw tool output it surfaced
(logs, diffs, traces, query results), and background-agent reports. Recap artifacts are not
agent output here; they have their own vocabulary above.

## Comprehension profile

The durable, person-specific calibration a [[#Decode]] reads: register, analogy policy,
native formats, and known confusion clusters. Lives in the knowledge bank, never in the
plugin — the mechanism is public, the person is not.

## Confusion record

A dated note that a particular output confused the person. Raw material a profile recompile
folds into the [[#Comprehension profile]]; it records, it never calibrates by itself.

## Interrogation ladder

The escalation a supervising person climbs when probing agent work: what changed → where
does it come from → what is it → why this way → prove it. A [[#Decode]] answers the rungs
that apply and never leaves the next one unaddressed.

## Promotion

Moving a session explanation into the knowledge bank as a concept doc, analogy preserved.
Always offered, never automatic.
