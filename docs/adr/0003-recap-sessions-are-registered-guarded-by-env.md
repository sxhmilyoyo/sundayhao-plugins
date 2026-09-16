---
status: accepted
date: 2026-09-14
implementation: 2.13.0
---

# Recap sessions are registered, guarded by environment

A recap session is a real session and gets a session note like any other. The obvious way to stop it
from recapping itself, and from re-arming the SessionStart cleanup that once deleted live folders, was
to start it with every hook disabled (`--settings '{"disableAllHooks":true}'`). We instead keep hooks
on and pass `SECOND_BRAIN_RECAP_OF=<subject session folder>` in its environment: SessionStart records
`recap_of` on the new note, and SessionEnd sees the marker, never requests a recap, and stamps the recap
session's own status `exempt`.

## Considered Options

**Disable all hooks in the recap session.** Rejected. Whether an inline settings override reaches
plugin hooks is undocumented, so the recursion guard would rest on a switch nobody can read in the
plugin's own code; the cleanup it also avoided no longer exists (ADR 0001); and it would make recap
sessions the only sessions the knowledge bank never records, contradicting the glossary.

**Register, but hide recap sessions from listings.** Deferred. Nothing hides them today; a filter on
`recap_of` can be added to ccfind or the SessionStart notice if the extra folders become noise.

## Consequences

One extra session folder per recap. Although the recap session runs with the vault as its working
directory, its note takes its subject's project: project names the domain the work belongs to, and the
bank itself is not a domain of work ([ADR-0004](0004-project-names-a-knowledge-bank-domain.md)). The
guard is a single environment variable, so anything that launches a recap session by hand must set it,
or that session will itself be recapped at exit.
