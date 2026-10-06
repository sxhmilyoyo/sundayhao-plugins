# Common Mistakes in Knowledge Bank Documentation

## Overview

Avoid these common mistakes when creating knowledge bank documentation. Each mistake includes examples of wrong and right approaches.

---

## Mistake 1: Insufficient Detail

### Wrong ❌
"Fixed a bug in the cache"

### Right ✅
"Fixed TieredCacheDataProvider.mget() to skip local cache updates when enableLocalCache=false, eliminating unnecessary CPU cycles (lines 200-297)"

### Why It Matters
Without specific details, future developers cannot understand what was fixed or how to avoid similar issues.

---

## Mistake 2: Missing Context

### Wrong ❌
"Changed the method"

### Right ✅
"Refactored getAdsTxtExcludedPublishers() from 27 lines of manual List→Set conversion to 7 lines using AbstractLiveConfig.getMapSetValue(), reducing code by 74%"

### Why It Matters
Context explains the rationale and impact of changes, not just what changed.

---

## Mistake 3: No Cross-References

### Wrong ❌
Document stands alone with no links to related documentation

### Right ✅
Document links to 5+ related concepts, components, and best practices

### Why It Matters
Cross-references enable discovery and show how concepts relate. Isolated documents become "knowledge islands".

---

## Mistake 4: Incomplete Code Examples

### Wrong ❌
Shows only "after" code

### Right ✅
Shows before/after comparison with line numbers and rationale:

```markdown
**Before** (lines 100-127):
[27 lines of manual conversion]

**After** (lines 100-107):
[7 lines using utility method]

**Rationale**: Reduces duplication, improves maintainability
```

### Why It Matters
Before/after comparisons demonstrate the improvement and help others learn the pattern.

---

## Mistake 5: No Decision Rationale

### Wrong ❌
"We chose approach A"

### Right ✅
"We chose approach A over B because:
1. 0.03% overhead negligible
2. Eliminates 60 lines duplication
3. Network I/O dominates
4. Simpler maintenance"

### Why It Matters
Future developers need to understand WHY decisions were made to evaluate if they still apply.

---

## Mistake 6: Missing Metrics

### Wrong ❌
"Improved performance"

### Right ✅
"Improved performance by eliminating 300ns overhead per 100 keys, which is 0.03% of 1ms network I/O time"

### Why It Matters
Quantitative data helps assess trade-offs and validates decisions with evidence.

---

## Mistake 7: Cross-References as Afterthought

### Wrong ❌
Write documentation first, then search for links to add

### Right ✅
Discover cross-references first (Phase 2), then write with context

### Why It Matters
Early cross-reference discovery ensures documentation integrates naturally with existing knowledge.

---

## Mistake 8: Vague Session Summaries

### Wrong ❌
"Worked on the filter system"

### Right ✅
"Refactored 5 filter classes to use builder pattern, reducing initialization code by 40% across 12 files (450 lines changed)"

### Why It Matters
Specific summaries enable quick understanding of scope and impact.

---

## Mistake 9: Missing File Paths and Line Numbers

### Wrong ❌
"Modified the configuration class"

### Right ✅
"Modified [project-a-live-config-impl].java:156-189 to add getAdsTxtExcludedPublishers() method"

### Why It Matters
Precise references allow future developers to find and understand changes quickly.

---

## Mistake 10: Forgetting Process Reflections

### Wrong ❌
Create only technical documentation, forget reflections entirely

### Right ✅
Create both technical docs AND process reflections for workflow insights

### Why It Matters
Process reflections capture HOW work was done, enabling continuous workflow improvement.

---

## Mistake 11: Superficial Cross-References

### Wrong ❌
Link to every document that mentions the same keyword

### Right ✅
Link only to documents with meaningful relationships (dependencies, implementations, related patterns)

### Why It Matters
Too many superficial links create noise and reduce the value of genuine connections.

---

## Mistake 12: Incomplete YAML Frontmatter

### Wrong ❌
```yaml
---
title: My Document
---
```

### Right ✅
```yaml
---
title: My Document
aliases: [Alternative Name]
tags: [category, topic]
type: concept
created: 2025-11-10
modified: 2025-11-10
project: [project-a-service]
---
```

### Why It Matters
Complete frontmatter enables searching, filtering, and organization across the knowledge bank.

---

## Mistake 13: Missing MOC Updates

### Wrong ❌
Create documentation but don't update relevant MOCs

### Right ✅
Add all new documents to appropriate MOC sections with proper organization

### Why It Matters
MOCs provide entry points for discovery. Missing MOC entries make documents hard to find.

---

## Mistake 14: No Bidirectional Cross-Linking

### Wrong ❌
Technical docs link to reflections, but reflections don't link back

### Right ✅
Ensure bidirectional links: tech docs ↔ reflections

### Why It Matters
Bidirectional links enable navigation in both directions and prevent one-way "knowledge islands".

---

## Mistake 15: Improvement Suggestions Written as Reflection Prose

### Wrong ❌
A reflection with "What Could Be Improved" sections or action-item checkboxes

### Right ✅
The reflection records what happened; each improvement becomes a proposal file in
`{KB}/_proposals/` via the Phase 2.7 scan (severity, concrete target, evidence), or a
best-practice doc when it is a validation technique

### Why It Matters
Nothing ever re-reads prose action items — 264 reflections accumulated them and no phase,
checklist, or script revisited one (ADR-0008). A queue the session-start notice counts gets
drained; prose does not.

---

## Mistake 16: Premature Completion Declaration

### Wrong ❌
Declare "session recap complete" without systematic verification

### Right ✅
Complete all phases of the completion checklist before declaring done

### Why It Matters
Premature completion leads to missing documentation, broken links, and incomplete knowledge capture.

---

## Mistake Prevention Checklist

Use this quick checklist to avoid common mistakes:

- [ ] Include specific details (file paths, line numbers, method names)
- [ ] Provide context and rationale for changes
- [ ] Discover 10-15 cross-references before writing
- [ ] Show before/after code examples
- [ ] Document decision rationale with reasons
- [ ] Include quantitative metrics
- [ ] Complete YAML frontmatter for all documents
- [ ] Create process reflections (not just technical docs)
- [ ] File improvement suggestions as `_proposals/` files or best-practice docs, never as reflection prose
- [ ] Establish bidirectional cross-links
- [ ] Update relevant MOCs
- [ ] Verify with quality standards checklist
- [ ] Run automated validation scripts
- [ ] Complete full verification before declaring done

---

## When Mistakes Happen

If mistakes are discovered:

1. **Acknowledge**: Don't hide or skip over the issue
2. **Fix**: Return to the relevant phase and correct
3. **Verify**: Re-run quality checks to ensure fix is complete
4. **Learn**: Document the mistake as an anti-pattern for future reference

---

## Resources

Related documentation:
- `quality-standards.md` - Detailed quality requirements
- `completion-checklist.md` - Systematic verification process
- `cross-reference-guide.md` - Cross-reference discovery methodology
- `scripts/verify_quality.sh` - Automated quality verification
- `scripts/validate_cross_references.sh` - WikiLink validation
