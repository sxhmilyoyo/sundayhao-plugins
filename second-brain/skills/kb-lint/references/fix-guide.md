# KB Lint Fix Guide

## Batch Stub Creation

When many broken WikiLinks are stub candidates (common in established KBs), batch-create them:

```yaml
---
title: "ComponentName"
type: component   # or concept, best-practice — inferred from naming pattern
status: stub
created: YYYY-MM-DD
project: {project}
tags:
  - stub
  - {project}/component
---

# ComponentName

> [!stub] This is a placeholder document.
> Created by kb-lint to resolve a broken WikiLink. Expand when this topic is documented.
```

### Classification Heuristics

Infer the document type from the WikiLink's naming pattern:

| Pattern | Example | Type | Directory |
|---------|---------|------|-----------|
| PascalCase | `BidVerifier`, `A2XHttpCallInvoker` | component | `projects/{project}/components/` |
| Title Case with spaces | `Dual Enforcement Model` | concept | `projects/{project}/concepts/` |
| kebab-case | `brazil-package`, `dependency-injection` | concept | `projects/{project}/concepts/` |

### Project Detection

Infer the project from the source file that contains the broken WikiLink:
- Source in `projects/a2x/` → `project: A2X`
- Source in `projects/aax/` → `project: AAX`
- Source in `projects/cc/` → `project: Claude Code`
- Source in `reflections/` or `rules/` → use the most-referenced project in the source file

## Alias Resolution

When a broken link is a near-match to an existing doc (e.g., `[[CompletableFuture]]` → `CompletableFuture Error Handling Patterns.md`), add the short form as an alias:

```yaml
aliases: [...existing aliases, "CompletableFuture"]
```

### Finding Near-Matches

For each broken link, search for existing docs where:
- The broken link text is a substring of the doc title
- The broken link text matches the first word(s) of the doc title
- The broken link text matches an existing alias

## Template Placeholder Removal

Generic WikiLinks from templates that were never filled in:
- `[[Related Concept 1]]`, `[[Related Concept 2]]`
- `[[Component Name]]`, `[[Practice Name]]`

Remove these from the source files — they add noise to lint reports without providing value.
