# Changelog - Second Brain Plugin

All notable changes to the second-brain plugin are documented in this file.
This covers plugin-level changes (hooks, tools, configuration, cross-cutting features).
For skill-specific changes, see the CHANGELOG.md in each skill's directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.0] - 2026-04-05

### Added
- **`_meta/index.md`**: Auto-generated content catalog covering all 188 KB documents, organized by project and type. Regenerated after every write operation via `generate_index.sh`.
- **`_meta/log.md`**: Chronological operation log tracking ingests, queries, lint passes, and index rebuilds via `append_kb_log()` in `obsidian_helpers.sh`.
- **`_meta/schema.md`**: Unified KB conventions file consolidating document types, frontmatter requirements, WikiLink standards, naming conventions, and operations reference.
- **kb-ingest skill**: Standalone source ingestion for articles, gists, docs, and URLs outside of Claude Code sessions. Interactive READ → DISCUSS → CREATE → INTEGRATE workflow following the LLM Wiki pattern.
- **kb-lint skill**: Knowledge bank health-check with 5 checks — broken WikiLinks, missing frontmatter, orphan documents, index drift, and stale content. Severity-graded reports at `_meta/lint-report-*.md`.
- **session-recap source detection**: Phase 1.4 scans session.md body sections (`## Generated Artifacts`, `## Plans`, `## Memory Snapshot`) and transcript for ingestible artifacts and references. Phase 2.4 plans which sources to ingest as KB docs.
- **ccfind `Ctrl-R`**: Refresh keybinding reloads session list without reopening fzf popup.

### Changed
- **knowledge-bank-lookup navigation**: "Index or MOC-First" strategy — `_meta/index.md` as fallback for projects without MOCs (CC, supply-opt).
- **knowledge-bank-lookup query write-back**: After high-value lookups, offer to file the synthesis as a KB document via kb-ingest workflow.
- **session-recap Phase 3 priority order**: Expanded from 5 to 7 levels — artifact-derived docs (5-8 WikiLinks) and reference-derived docs (5-8 WikiLinks) inserted at priorities 4-5.
- **session-recap Phase 5**: Added steps 5.2 (regenerate `_meta/index.md`) and 5.3 (append operation log).
- **Tiered WikiLink minimums**: Session-derived docs keep 10-15; ingested/artifact/reference docs require 5-8. `count_wikilinks.sh` accepts optional `min-links` parameter.

### Notes
- Inspired by [Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
- All changes are backward-compatible with existing KB documents

## [2.2.0] - 2026-04-08

### Changed
- **Reference-only session architecture**: Hooks no longer copy transcripts, agents, or plans into `segment-*` directories. `session.md` stores a `transcript_source` frontmatter property pointing to the original transcript at `~/.claude/projects/`. Eliminates ~99.8% of `_sessions/` storage overhead.
- **SessionEnd performance fix**: Removed 3 full-file grep operations (agents, plans, customTitle) that exceeded the 1.5s `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` cap. CustomTitle extraction now uses `tail -r` reverse-scan (14ms vs 322ms on 42MB transcripts).
- **Session folder lookup**: Replaced `find` (330ms on 500+ sessions) with temp file caching across hook lifecycle (<1ms). SessionStart writes folder path to `/tmp/`, SessionEnd/PreCompact read it back. Falls back to glob then mkdir.
- **PreCompact hook**: Replaced segment copying with a `compaction-points.txt` sidecar file that records line count + timestamp per compaction boundary.
- **session-recap Phase 1.1**: Reads `transcript_source` from session.md frontmatter first; falls back to `segment-*/transcript.jsonl` walking for old sessions.
- **SessionStart matchers**: Added `clear` and `compact` matchers for `/clear` and post-compaction events.
- **session-manager tag workflow**: No longer sets tags directly — reads existing tags from ccfind cache, matches user input against existing tags (exact, hyphenation, casing), presents suggestion table with usage counts, and confirms before setting. Promotes tag consistency.

### Added
- **ccfind `--by-name` / `Ctrl-N`**: Browse only named sessions (sessions with `session_name` set via `/rename`). Replaces the old `--by-task-tag` mode.
- **ccfind `Ctrl-R`**: Force cache refresh from within the fzf popup.
- **session-manager `session_name` auto-sync**: Reads `/rename` customTitle from transcript via `read_custom_title()` helper and sets `session_name` in session.md on every invocation.
- **tmux window rename**: session_resume.sh and session-manager skill rename the tmux window to `session_name` using `$TMUX_PANE` targeting. Reflects session name in tmux tab bar.
- **`read_custom_title()` helper**: New function in `obsidian_helpers.sh` — reads customTitle from session transcript via reverse-scan. Uses cwd hash (not git repo root) matching Claude Code's project directory structure.

### Removed
- **`task_tag` property**: Merged into `session_name` + `tags`. In practice, `task_tag` was identical to `session_name` in most sessions (one task = one session). Use `tags` for grouping related sessions.
- **ccfind `--by-task-tag` / `--task-tags`**: Replaced by `--by-name` / `Ctrl-N`.

### Fixed
- **SessionEnd hook cancelled**: Root-caused the "Hook cancelled" error — `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` (default 1.5s) silently caps per-hook `timeout` settings in hooks.json. Total execution reduced from ~2.16s to ~325ms (78% headroom).

## [2.1.0] - 2026-03-06

### Added
- **Auto memory snapshot**: SessionEnd hook copies `~/.claude/projects/{hash}/memory/` to session folder, with `## Memory Snapshot` section in session.md body
- **Session-manager skill**: `project` is now a customizable property (was hook-only); skill shows current session info on every invocation
- **ccfind**: Shell + fzf tool for searching and resuming sessions by metadata (`--by-tag`, `--by-task-tag`, keybindings for resume and open docs)

### Changed
- **session-recap v3.1.0**: Reads session.md as hub for metadata and content discovery; adds `session-folder` back-reference to all recap-created KB docs

### Removed
- **`generated_artifacts` property**: Dead placeholder — initialized but never populated

## [2.0.0] - 2026-01-12

### Added
- **Centralized session management**: Hooks for SessionStart, SessionEnd, PreCompact, and Resume
- **session.md**: Obsidian hub note with YAML frontmatter replaces `session-info.json` as single source of truth
- **Obsidian CLI integration**: All session note creation and property updates via CLI
- **Session-manager skill**: Tag sessions with `task_tag`, `tags`, and `summary` via Obsidian CLI
- **Dataview MOC**: `_sessions/MOC-Sessions.md` for task-first session browsing
- **Ghost cleanup**: Resume hook detects and removes ghost folders created by startup matcher firing during resume
- **hookSpecificOutput schema**: SessionStart hooks inject docs path into system prompt

### Fixed
- Obsidian datetime format: removed `Z` suffix for compatibility
- Empty list placeholders: skip `type="list"` with empty value to avoid `[""]`
- Obsidian CLI stdout pollution: redirect writes, filter loading messages on reads
- Obsidian app launches on CLI use: hide window via osascript after create

## [1.0.0] - 2026-01-08

### Added
- **session-recap skill**: Distill Claude Code sessions into knowledge bank documents (concepts, components, best practices, reflections, daily logs)
- **knowledge-bank-lookup skill**: Retrieve relevant context from knowledge bank with reflections-first strategy and WikiLink DFS traversal
- **Plugin configuration**: `~/.claude/plugins/config/second-brain/config.json` for knowledge bank path
- **Knowledge bank structure**: Projects, daily logs, sessions, index with Obsidian vault support

---

## Skill Changelogs

| Skill | Changelog |
|-------|-----------|
| session-recap | `skills/session-recap/CHANGELOG.md` |
| knowledge-bank-lookup | `skills/knowledge-bank-lookup/CHANGELOG.md` |
