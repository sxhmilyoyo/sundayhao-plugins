# Process Reflection Template

A reflection is a backward-looking **record** of how the work went, filed for later pattern
mining (see `GLOSSARY.md`). It records; it never proposes. An improvement suggestion —
missing tool, process change, check to add — is not a reflection section: route it to the
Phase 2.7 improvement scan ([improvement-scan.md](improvement-scan.md)).

Every claim cites evidence from the session: a file path, a command, a tool-call count, a
quote. A section with nothing evidenced for it is omitted, not filled.

```markdown
---
title: {Claim-shaped title, e.g. "Grep-first beat reading whole files in a 2k-line skill"}
aliases: []
tags: [{topic tags}]
type: reflection
created: {YYYY-MM-DD}
modified: {YYYY-MM-DD}
project: {domain}
session-folder: _sessions/{YYYY-MM-DD}/{session_id}
---

# {Title}

**Session**: [[{Daily Log Title}]] · **Category**: {reflection category folder}

## Overview

{2-3 sentences: what the session did, and why its process is worth recording.}

## What worked

- **{Approach or pattern}** — {what made it effective}.
  Evidence: {file, command, count, or quote from the transcript}

## What didn't / what failed

- **{Approach that failed or fought back}** — root cause: {why}.
  Evidence: {what was tried, where it broke}
  {If abandoned: what was tried before abandoning, and the takeaway.}

## Key learning

{One sentence a future session could act on.}

## Cross-References

- [[{Related reflection}]]
- [[{Concept or best practice}]]
- [[{Component}]]
- [[{Related session or daily log}]]
- [[{MOC}]]
```

Requirements:

- **≥ 5 WikiLinks** (target 5-8), discovered in Phase 2.2 before writing
- Frontmatter complete; `type: reflection`; `session-folder` present when recapping a folder
- File under `{KB}/reflections/{category}/` — categories are discovered dynamically from
  the vault's subdirectories
- Either body section may be omitted when nothing evidenced belongs in it; a reflection
  with neither is not worth creating
