# Changelog - WDYM Skill

All notable changes to the wdym skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.1] - 2026-10-10

### Fixed
- Step 0 sourced `skills/common/get_kb_path.sh` by a cwd-relative path, which resolves only
  from the plugin root; it now uses `${CLAUDE_PLUGIN_ROOT}`, as the hooks do.

### Changed
- Step 0 describes the profile as carrying the calibration not already in the person's
  always-on instructions. A person whose CLAUDE.md carries the register keeps only the
  evolving parts (confusion clusters, ladder, inbox) in the profile.

## [1.0.0] - 2026-10-06

### Added
- Initial release: on-demand decoder for agent output, triggered by self-directed
  comprehension/verification asks ("wdym", "what do you mean", "how did you verify",
  "prove it") with no named audience.
- Profile-driven calibration from `$KB_PATH/rules/comprehension-profile.md`; generic
  engineer-peer defaults when no profile exists.
- Interrogation-ladder checklist (what changed → where from → what is X → why this way →
  prove it) — never leave the next rung unaddressed.
- Three-rung format escalation: 80%-STE prose → diagram (every edge restated as a sentence)
  → one focused interactive HTML page. Videos out of scope.
- Verification posture: session-evidence citations, explicit verified-vs-inferred marking.
- Learning loop: dated confusion records appended to the profile Inbox; "recompile my
  profile" folds them in.
- Promotion offer (never auto-write) of landed explanations to knowledge-bank concept docs
  with the "## The Analogy (from the session's ELI5)" heading.
- `wdym debrief` end-of-task mode.
- Design inputs: Karpathy's 2026-10-02 format ladder (rungs 1–3 adopted) and a mining pass
  over 264 knowledge-bank reflections plus daily-log Human Input tables.
