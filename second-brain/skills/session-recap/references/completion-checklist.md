# Session Recap Completion Checklist

## Purpose

Systematic verification to prevent premature completion and ensure both technical documentation AND process reflections are created.

**CRITICAL**: Complete ALL sections below before declaring session-recap complete.

---

## 1. Technical Documentation Verification

Verify all applicable documentation has been created:

- [ ] **Components**: All modified/created components documented
- [ ] **Concepts**: All new patterns/principles documented
- [ ] **Best Practices**: All reusable methodologies documented
- [ ] **Daily Session Log**: Created with comprehensive summary

---

## 2. Process Reflections Verification

**Common Failure Mode**: Creating only technical docs and forgetting reflections entirely (50% work omission).

### Check Each Category

**Architecture Patterns**:
- [ ] Threading/concurrency patterns discovered?
- [ ] State management issues fixed?
- [ ] Design patterns applied (chain, facade, builder, etc.)?

**Development Workflows**:
- [ ] Existing utilities found (vs reimplementing)?
- [ ] Test-first development followed?
- [ ] Complex dependencies navigated successfully?
- [ ] Parallel subagents used effectively?

**Anti-Patterns**:
- [ ] Wrong approaches initially considered?
- [ ] Naming/directionality confusion encountered?
- [ ] Misunderstandings corrected?

**DX Improvements**:
- [ ] Search strategies that worked/failed?
- [ ] Missing documentation identified?
- [ ] Tool/command gaps discovered?

### Action Required

**If ANY answer is YES**: Create corresponding reflection document in `/reflections/[category]/`

**Minimum Requirement**: If session involved problem-solving or pattern discovery, at least 1 reflection MUST be created.

**Routing**: a reflection *records* what happened. An improvement suggestion — a tool to fix,
a check to add, a rule to change, a doc to make findable — is not a reflection: route it to
the Phase 2.7 improvement scan (Section 3 below).

---

## 3. Proposed Improvements Verification

**Common Failure Mode**: improvement ideas written as prose inside reflections, where nothing
ever revisits them (ADR-0008).

- [ ] Phase 2.7 scan ran across all seven categories (zero candidates is a legitimate outcome)
- [ ] Every mechanical/judgment candidate has a file in `{KB}/_proposals/` with complete
      frontmatter and `status: pending`
- [ ] Every technique-routed `validation-approach` candidate has a best-practice doc instead
- [ ] Daily log carries one line per proposal; `recap.log` one `proposed_improvement=` line each
- [ ] `verify_session_recap.sh` was called with `--proposals <files>` or `--no-proposals`,
      whichever is the truth

See [improvement-scan.md](improvement-scan.md) for categories, routing, and the file format.

---

## 4. Cross-Linking Verification

**Common Failure Mode**: Creating documentation without bidirectional links, resulting in "knowledge islands".

### Technical Docs → Reflections

- [ ] Component docs link to relevant reflections
- [ ] Concept docs link to relevant reflections
- [ ] Best practice docs link to relevant reflections
- [ ] Session log includes "Process Reflections" section with links

### Reflections → Technical Docs

- [ ] Each reflection links to relevant components
- [ ] Each reflection links to relevant concepts
- [ ] Each reflection links to session log

### MOC Updates

- [ ] MOC includes reflections section (verify section EXISTS)
- [ ] All new reflections added to MOC
- [ ] MOC organized by category (architecture/workflow/anti-patterns)

### Validation Commands

```bash
# Verify reflections folder exists and contains documents
ls -la ${KB_PATH}/reflections/

# Check cross-references from technical docs to reflections
grep -r "reflections" ${KB_PATH}/projects/{project}/
```

---

## 5. Quality Standards Verification

Verify all documents meet quality requirements:

- [ ] All documents have required YAML frontmatter
- [ ] Minimum cross-references met (10-15 for technical docs, 5-8 for reflections)
- [ ] All WikiLinks use correct syntax: `[[Document Name]]`
- [ ] All code references include file paths and line numbers
- [ ] MOC section for reflections exists (not just referenced)

---

## 6. Final Verification

**ONLY declare "✅ Session Recap Complete" after verifying ALL**:

- [ ] ✅ Technical documentation phase completed
- [ ] ✅ Process reflections phase completed (minimum 1 if applicable)
- [ ] ✅ Improvement scan completed and proposals consistent (Section 3)
- [ ] ✅ Cross-linking phase completed (bidirectional links verified)
- [ ] ✅ MOC updated with reflections section
- [ ] ✅ Quality standards met for all documents
- [ ] ✅ No broken WikiLinks
- [ ] ✅ Session log references BOTH technical docs AND reflections

### If ANY Item Unchecked

Return to the corresponding phase and complete it before declaring completion.

---

## Premature Completion Anti-Patterns

Avoid these vague completion statements:

❌ **Bad**: "Documentation created" (vague, incomplete)
❌ **Bad**: "Session recap complete" (without reflection verification)
✅ **Good**: "All 8 checklist items verified, session recap complete"

---

## Verification Script

Optional: Use validation script to check cross-references:

```bash
./scripts/validate_cross_references.sh document.md
```

Expected output:
- All WikiLinks resolve to actual files
- No broken references
- Exit code 0 for success

---

## Common Failure Patterns

### Pattern 1: Forgetting Reflections (50% Work Omission)
**Symptom**: Created only technical docs, no reflections folder
**Fix**: Run through Section 2 systematically, create at least 1 reflection

### Pattern 2: Missing Bidirectional Links (Knowledge Islands)
**Symptom**: Technical docs don't reference reflections
**Fix**: Add "See Also" section linking to relevant reflections

### Pattern 3: Premature Completion Declaration
**Symptom**: Declared complete without systematic verification
**Fix**: Complete all 6 verification sections before declaring done

### Pattern 5: Improvements Buried in Reflections
**Symptom**: "Could be improved" prose or action-item checkboxes inside a reflection
**Fix**: Move each to the Phase 2.7 scan — a proposal file in `_proposals/` (or a
best-practice doc for a validation technique); the reflection keeps only the record

### Pattern 4: MOC Not Updated
**Symptom**: Reflections created but not indexed in MOC
**Fix**: Verify MOC has reflections section, add all new reflection links

---

## Checklist Summary

Quick reference of critical items:

| Phase | Critical Check | Common Failure |
|-------|---------------|----------------|
| 1. Tech Docs | All doc types created | Missing component/concept docs |
| 2. Reflections | At least 1 reflection | Forgetting reflections entirely |
| 3. Proposals | Scan record ↔ `_proposals/` files agree | Improvements left as prose |
| 4. Cross-Linking | Bidirectional links | One-way links, knowledge islands |
| 5. Quality | Frontmatter, WikiLinks | Missing metadata |
| 6. Final | All 8 items checked | Premature completion |

---

## Success Criteria

Session recap is complete when:

✅ All technical documentation created and cross-referenced
✅ Process reflections created for key insights
✅ Proposed improvements filed for every scan candidate (or a truthful `--no-proposals`)
✅ Bidirectional cross-links established
✅ MOC updated with all new documents
✅ Quality standards met across all documentation
✅ No broken WikiLinks
✅ All 6 verification sections completed

**Only then declare**: "✅ Session Recap Complete - All verification checks passed"
