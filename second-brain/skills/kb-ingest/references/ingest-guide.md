# Ingest Guide

## Source Types

| Source | How to Read | Typical Output |
|--------|-------------|----------------|
| Markdown file | Read tool | Concept or best-practice doc |
| PDF document | Read tool (pages parameter) | Concept doc (may need distillation) |
| URL/article | WebFetch tool | Concept or best-practice doc |
| GitHub gist | WebFetch tool | Concept or best-practice doc |
| Inline text | Direct from user message | Depends on content |

## Classification Heuristics

| Source Content | KB Document Type | Placement |
|----------------|-----------------|-----------|
| Architectural pattern, design principle | Concept | `projects/{project}/concepts/` |
| Tool, library, system description | Component | `projects/{project}/components/` |
| Methodology, workflow, technique | Best Practice | `projects/{project}/best-practices/` |
| Cross-cutting pattern (applies to multiple projects) | Concept | `projects/cc/concepts/` or project-agnostic location |
| Original article (Study mode) | Source | `projects/{project}/sources/` |
| Numbered principles digest (Study mode) | Study | `projects/{project}/study/` |
| Per-theme learning notes (Study mode) | Study | `projects/{project}/study/` |

## Quality Standards for Ingested Docs

| Metric | Requirement |
|--------|-------------|
| WikiLinks | 5-8 minimum (use `count_wikilinks.sh doc.md 5`) |
| Frontmatter | `source-type` and `ingested-from` MUST be present |
| Size | Target concise, actionable knowledge — not a copy of the source |
| Cross-references | Run `search_cross_references.sh` to find WikiLink targets |

## Distillation for Large Sources

For sources >100KB, apply the [distillation guide](../../session-recap/references/distillation-guide.md):

1. **6-month test**: Will this be useful in 6 months? If not, skip.
2. **95% reduction**: Extract only actionable knowledge, not verbose traces
3. **BRAIN not ARCHIVE**: Preserve workflows, edge cases, decisions — not full content

## Updating Existing KB Pages

When new knowledge connects to existing docs:

1. **Add cross-references**: Insert WikiLinks in both the new and existing docs
2. **Revise outdated claims**: If new data contradicts old, update the old doc with a note
3. **Strengthen connections**: If new data supports existing patterns, add evidence
4. **Note supersession**: If new doc replaces old content, add `superseded-by:` to old doc's frontmatter
