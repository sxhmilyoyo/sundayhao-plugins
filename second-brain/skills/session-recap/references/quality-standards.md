# Quality Standards for Knowledge Bank Documentation

## Overview

All knowledge bank documentation must meet quality standards to ensure discoverability, maintainability, and actionability.

---

## YAML Frontmatter Requirements

Every document MUST include complete frontmatter:

```yaml
---
title: Document Title
aliases: [Alternative Name 1, Alternative Name 2]
tags: [category, topic, type]
type: concept|component|investigation|best-practice|daily-log
created: YYYY-MM-DD
modified: YYYY-MM-DD
project: [project-a-service]|[project-b-server]|Claude Code|[project-c]
---
```

### Project Field Values
- `[project-a-service]` - For [project-a] work
- `[project-b-server]` - For [project-b] work
- `Claude Code` - For Claude Code development
- `[project-c]` - For Supply Optimization work

---

## Cross-Reference Standards

### Minimum Requirements

| Document Type | Minimum | Target | When |
|---------------|---------|--------|------|
| Daily Session Log | 10 | 15 | Session recap |
| Concept Document | 10 | 15 | Session recap |
| Component Document | 10 | 15 | Session recap |
| Best Practice | 10 | 15 | Session recap |
| Process Reflection | 5 | 8 | Session recap |
| Artifact-derived doc | 5 | 8 | Session recap (from `docs/` artifacts) |
| Reference-derived doc | 5 | 8 | Session recap (from external references) |
| Standalone ingested doc | 5 | 8 | kb-ingest skill |
| Query synthesis doc | 5 | 8 | kb-lookup write-back |

### Verification

```bash
# Count WikiLinks (default min: 10)
./scripts/count_wikilinks.sh document.md

# Count WikiLinks with custom min (for ingested/reference docs)
./scripts/count_wikilinks.sh document.md 5

# Validate all links resolve
./scripts/validate_cross_references.sh document.md
```

---

## Code Reference Standards

Every code reference MUST include:
- **File path**: `/full/absolute/path/to/file.ext`
- **Line numbers**: `(lines 100-150)`
- **Context**: Why the change was needed

### Example

**✅ Good**:
```markdown
Fixed TieredCacheDataProvider.mget() to skip local cache updates when
enableLocalCache=false, eliminating unnecessary CPU cycles
(src/main/java/cache/TieredCacheDataProvider.java:200-297)
```

**❌ Bad**:
```markdown
Fixed a bug in the cache
```

---

## Documentation Quality Checklist

Run verification script:

```bash
./scripts/verify_quality.sh document.md

# Verifies:
# - Frontmatter completeness
# - Cross-reference count
# - File paths with line numbers
# - Code examples
# - Decision rationales
# - Metrics/measurements
```

### Manual Checks

- [ ] Session overview includes metrics (duration, files, lines, problems)
- [ ] Chronological progression is clear
- [ ] All files documented with line numbers
- [ ] Technical decisions explained with rationale
- [ ] Code examples show before/after
- [ ] Performance implications analyzed
- [ ] Cross-reference discovery completed (searched all categories)
- [ ] Minimum cross-references met
- [ ] Cross-references distributed across categories
- [ ] Cross-references are meaningful (not superficial)
- [ ] Lessons learned are actionable
- [ ] Build/test status recorded
- [ ] All WikiLinks use correct syntax: `[[Document Name]]`
- [ ] Frontmatter complete on all documents
- [ ] MOCs updated if needed

---

## WikiLink Syntax

### Correct Usage

**✅ Standard Link**:
```markdown
[[Document Name]]
```

**✅ Link with Alias**:
```markdown
[[Document Name|Display Text]]
```

**❌ Wrong Syntax**:
```markdown
[Document Name]  # Single brackets
(Document Name)  # Parentheses
```

---

## Document Structure Standards

### Daily Session Log Structure
1. Frontmatter with metadata
2. Session Overview (duration, files, outcome)
3. Key Discoveries (insights, not journey)
4. Problems Solved (concise list)
5. Work Completed (files modified, key changes)
6. Technical Decisions (only non-obvious choices)
7. Lessons Learned (actionable insights)
8. Knowledge Created/Updated (links to extracted docs)
9. Process Reflections (if applicable)

### Concept Document Structure
1. Frontmatter with metadata
2. Overview (purpose and context)
3. Core Principle or Architecture/Workflow
4. Usage Patterns (when to use, when NOT to use)
5. Examples with code
6. Anti-Patterns
7. Cross-References (10-15 WikiLinks)

### Component Document Structure
1. Frontmatter with metadata
2. Overview (purpose, package, file)
3. Architecture (class hierarchy, responsibilities)
4. Key Methods
5. Usage Examples
6. Testing Patterns
7. Cross-References (10-15 WikiLinks)

---

## Metrics and Measurements

### Required Metrics

Include quantitative data when documenting:

**Performance**:
- Time measurements (ms, μs)
- Throughput (requests/sec)
- Resource usage (CPU, memory)

**Code Changes**:
- Lines added/removed/changed
- Percentage reduction/increase
- File count modified

**Session**:
- Duration (hours)
- Problems solved (count)
- Tests created/modified (count)

### Example

**✅ Good**:
```markdown
Improved performance by eliminating 300ns overhead per 100 keys,
which is 0.03% of 1ms network I/O time
```

**❌ Bad**:
```markdown
Improved performance
```

---

## Decision Rationale Standards

Document non-obvious choices with rationale:

### Template

```markdown
**Decision**: [What was chosen]
**Alternatives**: [What else was considered]
**Rationale**:
1. [Reason 1 with data]
2. [Reason 2 with data]
3. [Reason 3 with data]
**Trade-offs**: [What was sacrificed]
```

### Example

**✅ Good**:
```markdown
**Decision**: Use approach A
**Alternatives**: Approach B
**Rationale**:
1. 0.03% overhead negligible
2. Eliminates 60 lines duplication
3. Network I/O dominates (1ms >> 300ns)
4. Simpler maintenance
**Trade-offs**: Slightly more complex initialization
```

---

## Anti-Patterns to Avoid

### Insufficient Detail
**Wrong**: "Fixed a bug"
**Right**: "Fixed TieredCacheDataProvider.mget() to skip local cache updates (lines 200-297)"

### Missing Context
**Wrong**: "Changed the method"
**Right**: "Refactored getAdsTxtExcludedPublishers() from 27 to 7 lines, reducing code by 74%"

### No Cross-References
**Wrong**: Document stands alone
**Right**: Document links to 5+ related concepts, components, best practices

### Incomplete Code Examples
**Wrong**: Shows only "after" code
**Right**: Shows before/after comparison with line numbers

### Vague Performance Claims
**Wrong**: "Much faster"
**Right**: "Reduced latency from 1.2ms to 0.9ms (25% improvement)"

---

## Quality Verification Process

### Step 1: Automated Checks
```bash
./scripts/verify_quality.sh document.md
./scripts/count_wikilinks.sh document.md
./scripts/validate_cross_references.sh document.md
```

### Step 2: Manual Review
Review manual checklist (see above)

### Step 3: Fix Issues
If any checks fail:
1. Return to relevant phase
2. Add missing content
3. Re-verify

### Step 4: Completion
Only declare complete when all standards met

---

## Success Criteria

Documentation meets quality standards when:

✅ All frontmatter fields present and valid
✅ Minimum cross-references met (10-15)
✅ All WikiLinks resolve correctly
✅ Code references include file paths and line numbers
✅ Metrics and measurements included
✅ Decision rationales documented
✅ Before/after examples provided
✅ Automated verification passes
✅ Manual checklist complete
