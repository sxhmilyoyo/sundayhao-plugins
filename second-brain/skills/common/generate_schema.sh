#!/bin/bash
# generate_schema.sh - Bootstrap _meta/schema.md from existing reference files
#
# Generates a unified KB conventions file. Run once to bootstrap, then maintain manually.
#
# Usage: ./generate_schema.sh [kb_path]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get_kb_path.sh"

KB_PATH="${1:-}"
if [ -z "$KB_PATH" ]; then
    KB_PATH=$(get_kb_path) || exit 1
fi
SCHEMA_FILE="$KB_PATH/_meta/schema.md"
mkdir -p "$KB_PATH/_meta"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%S')

cat > "$SCHEMA_FILE" << 'EOF'
---
title: Knowledge Bank Schema
type: schema
generated: TIMESTAMP_PLACEHOLDER
---

# Knowledge Bank Schema

Unified conventions for all knowledge bank documents. Referenced by session-recap, kb-ingest, kb-lookup, and kb-lint skills.

---

## Document Types

| Type | Directory | Purpose | WikiLink Min |
|------|-----------|---------|-------------|
| concept | `projects/{project}/concepts/` | Architectural patterns, design principles | 10 (session), 5 (ingest) |
| component | `projects/{project}/components/` | System components, classes, interfaces | 10 (session), 5 (ingest) |
| best-practice | `projects/{project}/best-practices/` | Reusable methodologies, techniques | 10 (session), 5 (ingest) |
| reflection | `reflections/{category}/` | Process insights, lessons learned | 5 |
| daily-log | `daily-log/` | Session archive logs | 10 |
| index | `_meta/index.md` | Auto-generated content catalog | N/A |
| log | `_meta/log.md` | Chronological operation log | N/A |
| schema | `_meta/schema.md` | This file — KB conventions | N/A |
| lint-report | `_meta/lint-report-*.md` | Health check results | N/A |

## Directory Layout

```
knowledge-bank/
├── projects/
│   └── {project}/
│       ├── concepts/
│       ├── components/
│       └── best-practices/
├── reflections/
│   ├── architecture-patterns/
│   ├── development-workflow/
│   ├── anti-patterns/
│   └── dx-improvements/
├── daily-log/
├── rules/
├── manual/
├── best-practices/           # Top-level (cross-project)
├── _index/                   # Human-curated MOCs
├── _meta/                    # Auto-generated operational files
│   ├── index.md              # Content catalog
│   ├── log.md                # Operation log
│   ├── schema.md             # This file
│   └── lint-report-*.md      # Lint reports
└── _sessions/
    └── YYYY-MM-DD/{session_id}/
        ├── session.md         # Hub note
        ├── docs/              # Session working documents
        └── memory/            # Auto-memory snapshot
```

## Required Frontmatter

### All KB Documents (MUST)

```yaml
---
title: Document Title
tags: [category, topic]
type: concept|component|best-practice|daily-log|reflection
created: YYYY-MM-DD
modified: YYYY-MM-DD
project: {project_name}
---
```

### Optional Fields

```yaml
aliases: [Alt Name 1, Alt Name 2]     # Alternative names for WikiLink resolution
status: active|deprecated|draft         # Document lifecycle status
complexity: basic|intermediate|advanced # Content difficulty
session-folder: _sessions/YYYY-MM-DD/{id}  # Back-reference to source session
source-type: session|artifact|reference|article|url|synthesis  # How knowledge entered KB
ingested-from: /path/to/source.md      # Provenance for non-session docs
query: "original query text"           # For synthesis docs (query write-back)
synthesized-from: [doc1, doc2]         # Source docs for synthesis
superseded-by: [[Newer Doc]]           # Points to replacement doc
related-concepts: [concept1, concept2]
related-components: [component1]
related-practices: [practice1]
```

## WikiLink Conventions

### Syntax

- Standard: `[[Document Title]]`
- With heading: `[[Document Title#Section]]`
- With alias: `[[Document Title|Display Text]]`
- Embed: `![[Document Title]]`

### Minimum Counts by Context

| Context | Minimum | Target |
|---------|---------|--------|
| Session-recap docs | 10 | 15 |
| Ingested/artifact docs | 5 | 8 |
| Reflections | 5 | 8 |
| Synthesis (write-back) | 5 | 8 |

### Distribution Guidelines

Distribute WikiLinks across categories:
- Concepts: 3-5
- Components: 3-5
- Best Practices: 1-2
- Recent Sessions/Reflections: 1-2
- MOCs: 1-2

## Naming Conventions

| Type | File Name Pattern | Example |
|------|-------------------|---------|
| Concept | Title Case with spaces | `Dual Enforcement Model.md` |
| Component | PascalCase or Title Case | `A2XHttpCallInvoker.md` |
| Best Practice | Title Case with spaces | `Investigation-First Development Pattern.md` |
| Reflection | kebab-case | `vertx-instance-variables-antipattern.md` |
| Daily Log | `YYYY-MM-DD [Topic].md` | `2026-01-15 Filter Migration.md` |

## Operations

| Operation | Skill | Trigger | Writes |
|-----------|-------|---------|--------|
| **Session Recap** | session-recap | Post-session | concepts, components, practices, reflections, daily-log |
| **Ingest** | kb-ingest | User provides source | concepts, components, practices |
| **Query** | kb-lookup | Service mention, investigation | Read-only (optionally writes back) |
| **Lint** | kb-lint | Manual health check | lint reports |
| **Index Rebuild** | generate_index.sh | After any write operation | _meta/index.md |
| **Log** | append_kb_log() | After any operation | _meta/log.md |

## Quality Standards

See `session-recap/references/quality-standards.md` for full details.

Key rules:
- Every document MUST have complete frontmatter
- Code references MUST include file paths and line numbers
- Technical decisions MUST include rationale
- Performance claims MUST include measurements
EOF

# Replace timestamp placeholder
sed -i '' "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/" "$SCHEMA_FILE" 2>/dev/null || \
    sed -i "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/" "$SCHEMA_FILE"

echo "Generated $SCHEMA_FILE" >&2
