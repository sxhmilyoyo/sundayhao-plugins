# Changelog - KB Ingest Skill

All notable changes to the kb-ingest skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.1.0] - 2026-04-08

### Added — Study Mode & Blog Synthesis

Refactored based on real-world usage (session 3ee1a81e). The original 4-step workflow assumed quick filing; actual usage showed deep interactive study → multi-layer output → shareable synthesis.

#### Two Engagement Modes
- **Quick mode**: Summarize → agree on doc type → file to KB (original behavior)
- **Study mode**: Theme-by-theme deep dive with online research → personal notes → three-layer KB output → optional blog/slack synthesis
- Mode selection via **AskUserQuestion tool** after reading the source

#### Study Mode Workflow (new Step 3: ENGAGE)
- **Present** each theme with core ideas and examples
- **Explore** online (WebSearch/WebFetch) for 2-3 related pieces per theme — counter-arguments, case studies, deeper explanations
- **Pause** for user to note takeaways in their own words
- **Capture** user's personal insights and reframings as first-class output

#### Three-Layer Output (new Step 4: CREATE for Study mode)
- **Source copy** in `projects/{project}/sources/` — original article with KB frontmatter
- **Digest** in `projects/{project}/study/` — numbered principles by category
- **Learning notes** in `projects/{project}/study/` — per-theme interactive discussion record
- Plus standard concept/component/best-practice docs

#### Synthesis Step (new Step 5: SYNTHESIZE)
- Optional blog post or Slack message synthesis after Study mode
- Selection via **AskUserQuestion tool** (Blog / Slack / Skip)
- Blog follows listicle format with analysis per takeaway (see `references/blog-synthesis-guide.md`)
- User owns their voice — polish, don't ghostwrite

#### New Document Types
- `type: study` — digests and learning notes
- `type: source` — original articles with KB frontmatter

#### New Reference Files
- `references/study-mode-guide.md` — theme walkthrough example, explore depth guidance, capturing user notes
- `references/blog-synthesis-guide.md` — blog writing prompt, output structure, voice ownership, Slack adaptation

### Changed
- **Step numbering**: 4 steps → 6 steps (READ → MODE SELECT → ENGAGE → CREATE → SYNTHESIZE → INTEGRATE)
- **Description**: Added trigger phrases — "take notes on this", "what are the key takeaways", "break this down for me"
- **AskUserQuestion tool**: Explicit at every decision point (mode select, quick mode confirmation, synthesis type)

## [1.0.0] - 2026-04-05

### Added — Initial Release
- READ → DISCUSS → CREATE → INTEGRATE workflow following the LLM Wiki pattern
- Standalone source ingestion for articles, gists, docs, URLs
- 5-8 WikiLink minimum (lower than session-recap's 10-15)
- Reuses session-recap templates and scripts
- `_meta/index.md` regeneration and `_meta/log.md` operation logging
- Batch ingest support
- `references/ingest-guide.md` — source types, classification, quality standards
