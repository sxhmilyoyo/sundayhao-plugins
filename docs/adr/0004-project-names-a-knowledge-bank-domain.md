---
status: accepted
date: 2026-09-14
---

# Project names a knowledge-bank domain

A session's project is the knowledge-bank domain its work belongs to, drawn from the fixed set of
domains the bank already files knowledge under. It is not the repository, directory or component the
session touched; those are tags. A working directory that matches no domain leaves the property empty,
so an unrecognised one is visibly missing rather than quietly invented.

The property was previously the working directory's basename, because that was free to compute at
registration. Recap reads the same property to decide where distilled knowledge is filed, so a basename
does not merely mislabel a session, it fabricates a domain: a directory called `data`, `src` or a bare
home-directory name becomes a peer of domains holding hundreds of documents. Three vocabularies had
already grown around the one word. Session notes held basenames, daily logs held display names, and the
index views filter on folder slugs, so two of the three joins matched almost nothing.

## Considered Options

**Keep the basename and let recap map it.** Rejected. It leaves every session note carrying a value no
reader can act on, and puts the mapping in the one place that runs last, long after the evidence about
what the session was for has been lost.

**Record the repository root instead.** Rejected as insufficient rather than wrong. It removes the
worst values, since a repository root is never `data`, but it still answers a different question than
the one recap asks, so recap would need its own mapping regardless.

**Two properties, one for the domain and one for the repository.** Rejected for now. Nothing yet reads a
repository property that tags do not already answer, and it would have to be added to the schema, the
lint checks and the session index.

## Consequences

An unfamiliar repository produces a session note with no project until a mapping is added, and that is
the intended signal. The mapping and each path's default tags live together in the plugin config, so
teaching the plugin about a new domain is one edit.

A session whose working directory is the knowledge bank itself, which is what a recap session runs in,
takes its subject's domain rather than the bank's own, since the bank is not a domain of work.

Every consumer validates the value against the configured domain set before acting on it. A value
outside the set is treated exactly like an empty one: unresolved. Nothing files knowledge under it, and
nothing launches unattended work for it; the need for a decision is surfaced to a person instead. This is
what makes leaving old notes alone safe, because a legacy basename is non-empty but is not a domain.

Existing notes keep their basenames. They are not migrated, because a basename cannot be turned into a
domain without knowing what the session was about, and guessing that retroactively is how the wrong
value spread in the first place.
