# Changelog - Knowledge Bank Lookup Skill

All notable changes to the knowledge-bank-lookup skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

**Note:** The most recent update is also shown in the "What's New" section of SKILL.md for immediate visibility.

---

## [2026-04-05] - v2.5.0 - Index Navigation, Query Write-Back & Operation Logging

### Added
- **Query Write-Back**: After high-value lookups, offer to file the synthesis as a KB document using kb-ingest workflow. Frontmatter: `source-type: synthesis`, `query`, `synthesized-from`.
- **Operation Logging**: SHOULD log queries to `_meta/log.md` via `append_kb_log()` for audit trail and usage tracking.
- **KB Schema reference**: Added `_meta/schema.md` to Reference Documentation section.

### Changed
- **Navigation Strategy**: Renamed from "MOC-First" to "Index or MOC-First". Added `_meta/index.md` as always-available entry point alongside service MOCs. Particularly useful for CC and supply-opt which lack MOCs.

---

## [2026-01-18] - v2.4.0 - Structure Refactoring & Terminology Standardization

**Type:** Documentation Refactoring - Improved Clarity and Progressive Disclosure

### Changed
- **SKILL.md Optimization**: Reduced from 455 lines to 230 lines (49% reduction)
- **Configuration moved up**: Now at line 42 (was line 331) for immediate visibility
- **Lookup Type Selection**: Condensed verbose section into scannable table
- **Best Practices**: Converted numbered list to compact table format
- **Subagent Response Format**: Converted verbose list to table format

### Added
- **`references/wikilink-traversal.md`** (~100 lines): Comprehensive WikiLink DFS documentation extracted from SKILL.md
  - Overview, DFS algorithm, link prioritization, cycle prevention
  - Traversal strategies by lookup type
  - Context budget allocation tables
  - JSON response field documentation
  - Troubleshooting guide
- **`references/frontmatter-retrieval.md`** (~95 lines): Property-based retrieval documentation extracted from SKILL.md
  - Priority properties table
  - 4-step lookup strategy
  - Search script documentation
  - Response enhancement fields
  - Best practices and troubleshooting
- **Advanced Features section** in SKILL.md: Brief overviews linking to detailed reference files
- **Anchor links** in templates.md for direct section linking

### Terminology Standardization

| Old Term (Ambiguous) | New Term (Clear) | Context |
|----------------------|------------------|---------|
| "lookup depth" | "lookup type" | Quick/Standard/Deep selection |
| "depth" in WikiLink | "hop count" | DFS traversal distance (1/2/3 hops) |
| "depth 1" | "1 hop" | WikiLink template instructions |

### Files Changed
| File | Action | Line Change |
|------|--------|-------------|
| `SKILL.md` | Major refactor | 455 → 230 |
| `references/wikilink-traversal.md` | Created | +100 |
| `references/frontmatter-retrieval.md` | Created | +95 |
| `references/templates.md` | Updated | Added anchors, terminology |
| `references/json-schemas.md` | Updated | Clarified depth = hop count |
| `CHANGELOG.md` | Updated | This entry |

### Benefits
- **Progressive Disclosure**: Essential info in SKILL.md, details in references
- **Improved Scannability**: Tables replace verbose prose
- **Clear Terminology**: No more confusion between lookup type vs hop count
- **Direct Linking**: Anchor links enable precise navigation from SKILL.md to templates
- **Configuration Accessible**: No longer buried at line 331

### Compatibility
- ✅ Fully backward compatible with v2.3.0
- ✅ All existing workflows unchanged
- ✅ New reference files complement existing structure

---

## [2026-01-09] - v2.3.0 - Frontmatter-Based Retrieval & Property Search

**Type:** Feature Enhancement - LLM-Optimized Document Discovery

### Added
- **Frontmatter-Based Retrieval Section** in SKILL.md:
  - Priority properties table for lookup optimization
  - Property-based filtering strategy (4-step process)
  - Property-based search script references
  - Response enhancement with property insights

- **New Search Scripts**:
  - **`scripts/search-by-property.sh`**: Search documents by frontmatter properties
    - Search by: type, status, complexity, relevance-to, category, package, tags
    - Options: `--count`, `--paths`, `--full`, `--json`
    - Project filtering support
    - Examples: `search-by-property.sh type concept`, `search-by-property.sh complexity advanced [project-a]`
  - **`scripts/find-related.sh`**: Graph traversal through relationship properties
    - Traverses: related-concepts, related-components, related-practices, implements, depends-on, used-by, supersedes, superseded-by, extracted-to
    - Configurable depth (`--depth N`)
    - Output formats: default, `--json`, `--graph`
    - Cycle prevention with visited tracking
    - Color-coded console output

### Changed
- **SKILL.md**: Added comprehensive Frontmatter-Based Retrieval section with:
  - Priority Properties table explaining each property's purpose
  - 4-step lookup strategy (MOC → Property Filtering → Graph Traversal → Version Awareness)
  - Script usage examples
  - Response enhancement documentation with `property_insights` field

### Benefits
- **Efficient Filtering**: Filter documents by type, status, complexity without reading content
- **Cross-Domain Matching**: Use `relevance-to` property for topic-based discovery
- **Graph Navigation**: Follow relationship properties to build context
- **Version Awareness**: Track document evolution through supersedes/superseded-by chains
- **Freshness Detection**: Prioritize recently reviewed documents

### Files Added
1. `scripts/search-by-property.sh` - Property-based document search
2. `scripts/find-related.sh` - Relationship graph traversal

### Files Modified
1. **SKILL.md** - Added Frontmatter-Based Retrieval section
2. **VERSION** - Updated to 2.3.0
3. **CHANGELOG.md** - This entry

### Compatibility
- ✅ Fully backward compatible with v2.2.0
- ✅ New scripts are standalone utilities
- ✅ Existing lookup workflows unchanged

---

## [2025-11-21] - v2.2.0 - WikiLink Following with DFS

**Type:** Major Feature - Comprehensive Knowledge Discovery

### Added
- **WikiLink Utilities (`scripts/wikilink-utils.sh`)**:
  - `extract_wikilinks()` - Extract all `[[WikiLinks]]` from markdown files
  - `resolve_wikilink()` - Resolve WikiLink names to file paths with priority search
  - `prioritize_wikilinks()` - Score links by relevance to query keywords
  - `dfs_traverse()` - Depth-First Search traversal with cycle prevention
  - File-based visited tracking (compatible with all bash versions)
- **Test Suite (`scripts/test-wikilinks.sh`)**:
  - 7 comprehensive tests for all WikiLink utilities
  - Validates extraction, resolution, DFS, cycle prevention
  - All tests passing ✅
- **WikiLink Following Section in SKILL.md**:
  - Complete explanation of DFS traversal strategy
  - Context budget allocation table
  - Link prioritization scoring system
  - Cycle prevention mechanisms
  - JSON response field documentation
- **New JSON Response Fields**:
  - `linked_concepts` - Array of concepts discovered through WikiLinks with depth tracking
  - `link_traversal` - Traversal statistics (links found/followed, max depth, strategy, path)
  - Enhanced `metadata` with `primary_documents` and `linked_documents` counts
- **WikiLink Example in references/examples.md**:
  - Complete example showing Pattern → Prerequisite → Implementation traversal
  - Demonstrates how DFS discovers Vert.x Event Loop Safety and CompositeFuture.all
  - Shows link prioritization and relevance scoring in action

### Changed
- **Updated All Lookup Workflows** (Quick/Standard/Deep):
  - Quick: Follow 1-hop WikiLinks (2-3 additional docs max)
  - Standard: Follow 1-2 hop WikiLinks prioritized by relevance (5-7 additional docs)
  - Deep: Full DFS traversal up to 3 hops (up to 20 total docs)
- **Updated Subagent Prompt Templates (references/templates.md)**:
  - Integrated WikiLink following into all three lookup types
  - Added bash commands for sourcing utilities and running DFS
  - Included instructions for prioritization and cycle prevention
- **Updated JSON Response Schema (references/json-schemas.md)**:
  - Documented `linked_concepts` field with all subfields
  - Documented `link_traversal` field with traversal statistics
  - Updated metadata fields to separate primary vs linked documents
  - Added usage notes for WikiLink traversal by lookup type
- **Updated SKILL.md**:
  - "What's New" section now references v2.2.0
  - Key Benefits mentions WikiLink following
  - Workflows updated to include WikiLink traversal steps
  - Response Format section lists new linked_concepts and link_traversal fields
- **Updated README.md**:
  - Version bumped to 2.2.0
  - Features section includes WikiLink Following
  - Structured Insights mentions linked_concepts
  - Version History includes v2.2.0 entry

### Context Budget Allocation

| Lookup Type | Primary Docs | WikiLink Budget | Total Lines |
|-------------|--------------|-----------------|-------------|
| Quick       | 600 lines    | 300 lines       | 900 lines   |
| Standard    | 1200 lines   | 750 lines       | 1950 lines  |
| Deep        | 4000 lines   | 3300 lines      | 7300 lines  |

### Link Prioritization Algorithm

- **+10 points**: Exact keyword match in WikiLink name
- **+5 points**: Pattern/Principle documents
- **+4 points**: Best practice documents
- **+3 points**: Component documents (Plugin, Provider, Builder, Extractor)

Links followed in priority order to maximize relevance within context budget.

### Cycle Prevention

- Visited documents tracked using temp file (`/tmp/wikilink_visited.*`)
- Each document visited only once per traversal
- DFS stops at max depth or max document limits
- Graceful handling of broken links (logged but don't fail)

### Benefits

- **Complete Information**: DFS ensures no connected knowledge is missed
- **Automatic Discovery**: Finds prerequisites, related patterns, and implementations via natural document links
- **Context-Aware**: Prioritizes relevant links based on query keywords
- **Efficient Navigation**: Follows the knowledge bank's natural Obsidian WikiLink structure
- **Depth Tracking**: Know which concepts are prerequisites (depth 1) vs implementation details (depth 2-3)

### Files Added
- `scripts/wikilink-utils.sh` (331 lines) - Core WikiLink utilities
- `scripts/test-wikilinks.sh` (249 lines) - Comprehensive test suite

### Files Updated
- `SKILL.md` - Added WikiLink Following section (100+ lines)
- `references/templates.md` - Updated all 3 lookup templates with WikiLink workflows
- `references/json-schemas.md` - Documented new fields
- `references/examples.md` - Added comprehensive WikiLink example
- `README.md` - Updated features and version
- `CHANGELOG.md` - This entry

### Test Results
```
Testing WikiLink Utilities
==========================================
✓ PASS: Extracted 117 WikiLinks from [project-a] MOC
✓ PASS: Resolved WikiLink to file path
✓ PASS: Relevance scoring (exact match scored higher)
✓ PASS: WikiLink prioritization (relevant links first)
✓ PASS: DFS traversal (10 docs visited, max depth 1)
✓ PASS: Cycle prevention (visited count unchanged on re-traversal)
✓ PASS: Show WikiLink paths utility

Tests run: 7
Tests passed: 7 ✅
Tests failed: 0
```

---

## [2025-11-16] - v2.1.0 - Common Utilities Integration

**Type:** Infrastructure improvement - Portable path configuration

### Changed
- **Removed hardcoded paths**: All hardcoded knowledge bank paths replaced with dynamic resolution
- **Integrated with common utilities**: All 7 shell scripts now use `~/.claude/skills/common/get_kb_path.sh`
- **No default fallback**: System errors out if KB_PATH not configured (forces proper setup)
- **Updated all documentation**: SKILL.md, references, and examples use `{KB_PATH}` placeholder

### Added
- Configuration section in SKILL.md explaining path resolution priority
- Clear error messages when KB path not configured
- Verification command: `~/.claude/skills/common/setup_kb_path.sh`

### Files Updated
- **7 shell scripts** in `scripts/`: Now source common utilities
- **SKILL.md**: Added Configuration section, updated Base Path reference
- **references/templates.md**: All paths use `{KB_PATH}` placeholder
- **references/examples.md**: Examples show dynamic path usage
- **references/knowledge-bank-structure.md**: Removed hardcoded path
- **references/session-documentation.md**: Command uses `{KB_PATH}` placeholder
- **~/.claude/skills/common/get_kb_path.sh**: Removed default fallback

### Path Resolution Priority
1. `~/.claude/CLAUDE.md` (PRIMARY - recommended)
2. `CLAUDE_KB_PATH` environment variable (temporary override)
3. `~/.claude/config/kb.conf` (alternative)
4. **ERROR** if none found (no default fallback)

### Benefits
- **Fully portable**: Works on any machine with proper configuration
- **Zero tolerance**: Forces users to configure path properly
- **Single source of truth**: Path configured in one place
- **Clear errors**: Helpful messages guide users to fix configuration
- **Consistent with session-recap**: Both skills use same utilities

### Migration for Existing Users
Your existing setup should work automatically if `~/.claude/CLAUDE.md` is properly configured with the Knowledge Bank Integration section.

To verify: `~/.claude/skills/common/setup_kb_path.sh`

---

## [2025-11-15] - v2.1.0 - Structure Optimization

**Type:** Documentation restructuring following Claude Code best practices

### Changed
- **SKILL.md Optimization**: Reduced from 846 lines to 229 lines (73% reduction)
- Moved detailed content to `references/` directory for progressive disclosure:
  - `references/templates.md` - All subagent prompt templates (267 lines)
  - `references/examples.md` - Integration examples (135 lines)
  - `references/json-schemas.md` - Response format specifications (69 lines)
  - `references/knowledge-bank-structure.md` - Directory structure (61 lines)
  - `references/optimization-techniques.md` - Context efficiency techniques (45 lines)
  - `references/session-documentation.md` - Documentation process (40 lines)
- Simplified "What's New" section to single line with link to CHANGELOG
- Added "Quick Start" section for most common usage pattern
- Added comprehensive "Reference Documentation" section with links to all reference files

### Rationale
- **Progressive Disclosure**: Follows skill-creator best practices (metadata → SKILL.md → bundled resources)
- **Context Efficiency**: SKILL.md remains lean, detailed content loaded only when needed
- **Better Organization**: Related content grouped in topic-specific reference files
- **Easier Maintenance**: Updates to templates/examples don't bloat main skill file
- **Improved Usability**: Clear navigation to detailed content when required

### Benefits
- SKILL.md now under 250 lines (recommended limit for skills)
- All functionality preserved and properly referenced
- Follows official Claude Code skill structure guidelines
- References loaded on-demand for maximum efficiency

---

## [2025-11-08] - v2.1.0 - Reflections Integration

**Type:** Feature addition - Process reflection integration

### Added
- **Reflections-First Strategy**: All lookup workflows now check `/reflections/` directory FIRST before MOC lookups
- Added `reflections/` directory to knowledge bank structure diagram (lines 93-97)
- Added `reflection_insights` field to JSON response schema with 5 subfields:
  - `past_mistakes`: Documented failures to avoid
  - `proven_approaches`: What worked well in similar situations
  - `workflow_gotchas`: Process friction points to watch for
  - `tool_gaps`: Missing tools that would help
  - `meta_insights`: Patterns across multiple sessions
- New automatic trigger: **"Process Learning"** for queries like "how did we handle X before", "past lessons on", "what went wrong with"
- Reflection check step (step 0) added to all lookup workflows:
  - Quick Lookup: Check last 3-5 recent reflections
  - Standard Lookup: Search reflections for topic/service matches
  - Deep Lookup: Comprehensive reflection analysis for patterns
  - CC Lookup: Search CC-related reflections

### Changed
- Updated all workflow descriptions to include reflection checks as step 0
- Updated all template prompts to check reflections first
- Updated document counts: [project-a] (81), [project-b] (18), CC (7), [project-c] (2), Total (172)
- Updated activity metrics based on last 30 days ([project-a]: 53 modified, [project-b]: 18, CC: 7, [project-c]: 2)

### Rationale
- **Learn from Past Mistakes**: Extract documented failures to avoid repeating errors
- **Apply Proven Approaches**: Use workflows and techniques that worked well before
- **Workflow Friction Awareness**: Identify and address process pain points proactively
- **Continuous Improvement**: Build on past experience rather than starting from scratch
- **Context-Rich Guidance**: Combine technical documentation with workflow insights for better recommendations

### Technical Details
- Reflections stored at `{KB_PATH}/reflections/`
- Reflections use format: `YYYY-MM-DD [Topic].md`
- Contains 5 reflection questions: what worked, what didn't, what failed, improvements, what would make it seamless
- Lighter than technical docs: 5-8 cross-references vs 10-15 for technical documentation
- Separate from technical docs: Reflections = HOW you work, Technical docs = WHAT you build

### Validation Results
- ✅ Structure verification: PASSED
- ✅ Document count drift: 0% (perfect accuracy)
- ✅ All workflows updated consistently
- ✅ JSON schema includes reflection_insights in all lookup types
- ✅ All templates include reflection check as step 0

### Inspired By
- session-recap skill v2.1.0: Process reflection capability
- Philosophy: "Knowledge Bank = BRAIN (remember what matters), not ARCHIVE (preserve everything)"

---

## [2025-11-06] - v2.0.1 - Production Packaging

**Type:** Release packaging

### Added
- README.md with comprehensive installation and usage documentation
- VERSION file for version tracking
- Production-ready package structure
- SHA256 checksum for package integrity

### Changed
- Version bumped to v2.0.1 for production release
- Package now includes all necessary documentation for standalone distribution

### Rationale
- Creates a complete, distributable package
- Enables easy installation and setup
- Provides comprehensive documentation for new users
- Establishes version control for future updates

**Released as:** knowledge-bank-lookup-v2.0.1.tar.gz

---

## [2025-11-06] - Separated Changelog from SKILL.md

**Type:** Documentation improvement

### Changed
- Moved full update history from SKILL.md to this CHANGELOG.md file
- Replaced verbose "Update Log" section with concise "What's New" section in SKILL.md
- SKILL.md now shows only the latest update with link to full history

### Rationale
- Reduces SKILL.md context consumption (removed ~70 lines of historical updates)
- Keeps skill file focused on operational content ("how to use")
- Follows standard practice for changelog management
- Maintains discoverability through "What's New" section and clear reference
- Improves long-term maintainability as update history grows

---

## [2025-11-06] - Document Count Update & Daily Log Exclusion

**Type:** Count update + Structural change (following SOP Scenario 4)

### Changed
- Updated all document counts to reflect current state (lines 85-132)
- Removed daily log references throughout skill (daily logs moved to `/daily-log/` for tracking only)
- Removed daily/ subdirectories from structure diagram (lines 85-113)
- Removed daily log steps from Standard Lookup workflow (line 175)
- Removed daily log steps from CC Lookup workflow (lines 221-226, 240-246)
- Removed daily log steps from Deep Lookup template (line 502)
- Removed daily log references from Standard Lookup template (line 417)
- Removed daily log references from Integration Examples (line 623)
- Removed recent_work references from Main Agent Response Construction (lines 651-658)
- Updated Required documentation types to reflect `/daily-log/` location (line 792)
- Updated cross-reference target to "per document" instead of "per daily log" (line 801)
- Updated project documentation routing to exclude daily/ (lines 807-812)

### Fixed
- Session documentation rule path - removed `/guides/` (line 788)

### Added
- Note about [project-c] having no MOC yet (line 132)
- Note explaining daily logs exclusion rationale

### Document Counts
- **[project-a]:** 75 docs (was 87) ✅ (-12 daily logs extracted)
- **[project-b]:** 16 docs (was 15) ✅ (+1 doc)
- **CC:** 7 docs (was 8) ✅ (-1 daily log extracted)
- **[project-c]:** 2 docs (was 3) ✅ (-1 daily log extracted)
- **Total:** 157 docs (was 129) ✅ (+28 docs including manuals, adjusted for daily logs)
- **Daily logs:** ~40 files moved to `/daily-log/` for tracking purposes only

### Rationale
- Daily logs are now maintained separately in `/daily-log/` for historical tracking
- Lookups should focus on permanent documentation (concepts, components, best practices)
- Reduces lookup noise and improves context efficiency
- Maintains cleaner separation between active knowledge and historical logs

**Validation:** ✅ All checks passed (0% drift, all paths verified, [project-c] MOC documented)

**Updated by:** Knowledge Bank Maintenance
**Time spent:** 35 minutes (following SOP Scenario 4)

---

## [2025-11-02] - Added Claude Code (CC) Project & Comprehensive SOP

**Type:** Major update - New project addition + Infrastructure improvements

### Added
- CC/Claude Code/ClaudeCode to service triggers (line 24)
- CC components (hook, subagent, build-interceptor, build-executor) to component triggers (line 26)
- CC project with 8 documents, no MOC yet (lines 66-70)
- CC-specific lookup workflow with direct navigation (lines 176-225)
- Comprehensive SOP for future updates (SOP-KNOWLEDGE-BANK-UPDATES.md)
- 7 automation scripts for maintenance:
  - scripts/verify-structure.sh (structure verification)
  - scripts/count-documents.sh (document counting)
  - scripts/detect-drift.sh (drift detection with thresholds)
  - scripts/compare-structure.sh (SKILL vs filesystem comparison)
  - scripts/check-mocs.sh (MOC existence verification)
  - scripts/verify-paths.sh (path resolution testing)
  - scripts/extract-triggers.sh (trigger pattern discovery)
- Quick reference guide (QUICK-REFERENCE.md)

### Changed
- Updated directory structure to reflect projects/ organization (lines 46-95)
- Fixed all path references to use projects/ structure
- Updated documentation section with project routing (lines 779-784)

### Document Counts
- **[project-a]:** 87 docs (73 recent) ✅
- **[project-b]:** 15 docs (15 recent) ✅
- **CC:** 8 docs (8 recent) ✅ **NEW**
- **[project-c]:** 3 docs (3 recent) ✅
- **Total:** 130 docs (was 129, +1 doc)

**Validation:** All 8 checks passed

**Updated by:** Knowledge Bank Maintenance
**Time spent:** 180 minutes (infrastructure setup)

---

## Changelog Format

Each entry includes:
- **Date** in [YYYY-MM-DD] format
- **Type** of update (Major update, Count update, Structural change, etc.)
- **Changed/Added/Fixed/Removed** sections following Keep a Changelog format
- **Document Counts** showing before/after states
- **Validation** results
- **Updated by** and **Time spent** for tracking maintenance effort

For the most recent update, see the "Update Log" section in SKILL.md.
