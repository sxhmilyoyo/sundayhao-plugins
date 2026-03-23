---
title: YYYY-MM-DD [Brief Topic Description]
aliases: []
tags: [{project}/daily-log, YYYY-MM]
type: daily-log
status: archived
session-id: [UUID or descriptive-id]
session-name: [from session.md session_name]
session-folder: _sessions/YYYY-MM-DD/{session_id}
duration-hours: [X]
outcome: complete | partial | blocked
topics-covered:
  - [topic1]
  - [topic2]
extracted-to:
  - "[[Concept Name]]"
  - "[[Component Name]]"
related-sessions: []
supersedes:
superseded-by:
created: YYYY-MM-DD
modified: YYYY-MM-DD
project: [ProjectName]
---

# YYYY-MM-DD [Topic]

> [!note] Daily Log Purpose
> This is an archival record of the session for historical reference. This log is created as the LAST step (low priority). Primary focus should be on extracting concepts, components, and best practices to the main knowledge bank (`/projects/`).

## Session Overview

> [!abstract] Summary
> [2-3 sentences: What was accomplished, outcome, and current status]

| Metric | Value |
|--------|-------|
| **Session Name** | [from session.md] |
| **Duration** | [X hours] |
| **Status** | ✅ Complete / ⚠️ Partial / ❌ Blocked |
| **Files Modified** | [Count] |
| **Lines Changed** | ~[Number] lines |
| **Outcome** | [Brief result - feature ready, investigation complete, etc.] |

## Key Discoveries

> [!tip] Focus on INSIGHTS, not investigation journey

1. **[Discovery 1]**: [What was learned - architecture, pattern, constraint]
2. **[Discovery 2]**: [Critical finding or constraint]
3. **[Discovery 3]**: [Design pattern or best practice identified]

## Investigation Documents

[IF external investigation docs exist]

**Knowledge distilled from investigation at:**
`/path/to/original/investigation/` (XX KB total)

**Distilled into:**
- [[Concept Name]] - [One-line description] (X KB)
- [[Component Name]] - Updated with [what was added]
- [[Pattern Name]] - Reusable pattern extracted

**Key Sections** (from investigation):
- [Section 1: e.g., "Workflow analysis (6-step sequence)"]
- [Section 2: e.g., "Edge cases and constraints"]
- [Section 3: e.g., "Performance characteristics"]

---

## Problems Solved

[Concise list - keep to essentials]

### 1. [Problem Title]

**Problem**: [What was broken/needed]
**Solution**: [How it was fixed - key approach only]
**Result**: [Measurable outcome]

## Work Completed

[Concise list of key changes - focus on WHAT changed and WHY, not detailed code]

**Files Modified**:
1. `/full/path/to/File.java` (lines X-Y) - [One-line summary of change]
2. `/full/path/to/Another.java` (lines X-Y) - [One-line summary]

**Key Changes**:
- [Change 1: What and why in one sentence]
- [Change 2: What and why in one sentence]
- [Change 3: What and why in one sentence]

**Build Status**: ✅ All tests passing | ⚠️ Known issues | ❌ Blocked

---

## Implementation Ready

[IF investigation complete but not yet implemented]

**Status**: ✅ Ready for implementation | ⚠️ Needs review | 📋 Planning phase
**Effort Estimate**: [X hours/days]
**Risk Level**: Low | Medium | High
**Next Steps**: [What needs to happen next]

---

## Technical Decisions

[Only non-obvious choices - if obvious, skip this section]

### [Decision Name]

**Choice**: [What was decided]
**Rationale**: [Why - key reasons only, 2-3 bullets max]
**Impact**: [Effect on system]

---

## Lessons Learned

> [!warning] Actionable insights - keep to 3-5 key lessons

1. **[Lesson Title]**: [What was learned - one sentence]
2. **[Lesson Title]**: [Principle or pattern discovered]
3. **[Lesson Title]**: [Practice to adopt/avoid]

## Session Insights

> [!info] Educational insights generated during this session
> These are `★ Insight` blocks from the explanatory-output-style plugin. Each insight MUST be included here, and SHOULD be extracted to appropriate knowledge bank documents.

### Insight 1
> `★ Insight ─────────────────────────────────────`
> [Insight content]
> `─────────────────────────────────────────────────`

**Classification**: [Concept / Component / Best Practice / Reflection / Context only]
**Extracted to**: [[Document Name]] (if applicable) or "Daily log only"

### Insight 2
> `★ Insight ─────────────────────────────────────`
> [Insight content]
> `─────────────────────────────────────────────────`

**Classification**: [Concept / Component / Best Practice / Reflection / Context only]
**Extracted to**: [[Document Name]] (if applicable) or "Daily log only"

## Knowledge Created/Updated

> [!info] Knowledge Extraction
> Daily logs link TO knowledge bank, but are not primary knowledge themselves. Update the `extracted-to` frontmatter property with links to documents created from this session.

**New Knowledge Extracted**:
- [[Concept Name]] - New pattern/architecture discovered
- [[Component Name]] - New component documented
- [[Pattern Name]] - Reusable approach extracted

**Existing Knowledge Updated**:
- [[Existing Component]] - Added methods/behavior
- [[Existing Concept]] - Enhanced with new insights

**Best Practices Applied**:
- [[best-practice/category/Practice Name#Decision Framework]]

## Cross-References

> [!info] Related Knowledge
> Populate the frontmatter `related-sessions` and `extracted-to` properties for graph navigation.

**Related Knowledge**:
- [[Concept A#Core Principle]] - Applied in this session
- [[Concept B]] - Built upon
- [[Component C]] - Modified/used

**Related Sessions**:
- [[YYYY-MM-DD Previous Session]] - [Connection to prior work]

**Maps of Content**:
- [[{Project} MOC]]

---

> [!example] Session Metadata
> | Field | Value |
> |-------|-------|
> | **Session Date** | YYYY-MM-DD |
> | **Total Duration** | [X hours] |
> | **Final Status** | ✅ Complete / ⚠️ Partial / 📋 Next Steps Required |
> | **Knowledge Extracted** | [X concepts + X components + X patterns] |

> [!important] Daily Logs are Archival
> This log lives in `/daily-log/` for historical reference. Primary knowledge has been extracted to `/projects/{project}/concepts/`, `/projects/{project}/components/`, and `/projects/{project}/best-practices/`.
